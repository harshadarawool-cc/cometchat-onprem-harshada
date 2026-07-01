###############################################################################
# Bastion — small jump host on the edge subnet, reached via IAP SSH only.
# Doubles as the Ansible control host (has private-network SSH to all VMs).
# No public IP. Optional: with IAP TCP forwarding you can SSH every VM directly
# and skip this; kept for a simple "run Ansible from inside the VPC" workflow.
###############################################################################
resource "google_compute_instance" "bastion" {
  name         = "${var.name_prefix}-bastion"
  machine_type = var.bastion_machine_type
  zone         = var.zone
  tags         = ["bastion"]
  labels       = merge(var.labels, { role = "bastion" })

  boot_disk {
    initialize_params {
      image = var.vm_image
      size  = var.boot_disk_gb
      type  = var.disk_type
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.edge.id
    network_ip = cidrhost(var.subnet_edge_cidr, 10)
    # no access_config => no public IP (IAP only)
  }

  metadata = merge(
    { enable-oslogin = "FALSE" },
    var.ssh_public_key != "" ? { ssh-keys = "${var.ssh_user}:${var.ssh_public_key}" } : {}
  )

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  allow_stopping_for_update = true
}
