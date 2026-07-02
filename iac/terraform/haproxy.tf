###############################################################################
# Edge — standalone HAProxy VMs (replaces the GCP L4 Network LB).
#
# The ONLY public entry point. Each HAProxy VM has its own EXTERNAL static IP;
# DNS round-robins every facing host across BOTH IPs (active-active). HAProxy
# does L4 **SNI passthrough** (it does NOT terminate TLS) and routes by the TLS
# SNI hostname to a per-service NodePort on the RKE2 agent nodes. TLS terminates
# at the per-pod nginx sidecar. See ansible/roles/haproxy + docs/HAPROXY-EDGE.md.
#
# Why standalone VMs instead of a cloud LB: RKE2 ships no cloud-controller, so
# `type: LoadBalancer` never gets an IP; and we want SNI-passthrough to per-pod
# TLS (data-residency: TLS terminates inside the pod, never at the edge).
###############################################################################

# One reserved EXTERNAL IP per HAProxy VM (stable across VM recreate).
resource "google_compute_address" "haproxy" {
  count        = var.haproxy.count
  name         = "${var.name_prefix}-haproxy-${count.index + 1}-ip"
  region       = var.region
  address_type = "EXTERNAL"
}

resource "google_compute_instance" "haproxy" {
  count        = var.haproxy.count
  name         = "${var.name_prefix}-haproxy-${count.index + 1}"
  machine_type = var.haproxy.machine_type
  zone         = var.zone
  tags         = ["haproxy"]
  labels       = merge(var.labels, { role = "haproxy" })

  boot_disk {
    # CMEK for encryption-at-rest when provided; else Google-managed keys (still at-rest).
    kms_key_self_link = var.disk_kms_key != "" ? var.disk_kms_key : null
    initialize_params {
      image = var.vm_image
      size  = var.boot_disk_gb
      type  = var.disk_type
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.edge.id
    # edge subnet: bastion=.10, haproxy=.21,.22,...
    network_ip = cidrhost(var.subnet_edge_cidr, 21 + count.index)
    access_config {
      nat_ip = google_compute_address.haproxy[count.index].address
    }
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

# Public IPs of the edge — DNS round-robins facing hosts across ALL of these.
output "haproxy_ips" {
  description = "Public IPs of the HAProxy edge VMs. DNS round-robins facing hosts across all of them."
  value       = google_compute_address.haproxy[*].address
}

# Internal IPs (for the ansible haproxy backends / inventory).
output "haproxy_internal_ips" {
  description = "Internal edge-subnet IPs of the HAProxy VMs."
  value       = google_compute_instance.haproxy[*].network_interface[0].network_ip
}
