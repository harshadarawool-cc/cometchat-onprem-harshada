###############################################################################
# RKE2 nodes — servers (control plane) + agents (workers) on the cluster subnet.
# No public IPs. Agents are tagged "rke2-agent" so the edge LB / health checks
# can reach ingress-nginx (hostPort 80/443) on them.
###############################################################################
locals {
  rke2_nodes = merge(
    { for i in range(var.rke2_server.count) : "k8s-master-${i + 1}" => {
      ip = cidrhost(var.subnet_cluster_cidr, 11 + i), machine = var.rke2_server.machine_type, tag = "rke2-server"
    } },
    { for i in range(var.rke2_agent.count) : "k8s-worker-${i + 1}" => {
      ip = cidrhost(var.subnet_cluster_cidr, 21 + i), machine = var.rke2_agent.machine_type, tag = "rke2-agent"
    } },
  )
}

resource "google_compute_instance" "rke2" {
  for_each       = local.rke2_nodes
  name           = "${var.name_prefix}-${each.key}"
  machine_type   = each.value.machine
  zone           = var.zone
  tags           = ["rke2", each.value.tag]
  labels         = merge(var.labels, { role = each.value.tag })
  can_ip_forward = true # pod overlay networking

  boot_disk {
    initialize_params {
      image = var.vm_image
      size  = var.boot_disk_gb
      type  = var.disk_type
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.cluster.id
    network_ip = each.value.ip
    # no access_config => no public IP
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

output "rke2_ips" {
  description = "Internal IPs of RKE2 nodes."
  value       = { for k, n in local.rke2_nodes : "${var.name_prefix}-${k}" => n.ip }
}
