###############################################################################
# RKE2 nodes — servers (control plane) + agents (workers) on the cluster subnet.
# No public IPs. Agents are tagged "rke2-agent" so the HAProxy edge can reach the
# per-service NodePorts (30000-32767) on them (SNI passthrough -> pod nginx TLS sidecar).
###############################################################################
locals {
  rke2_nodes = merge(
    { for i in range(var.rke2_server.count) : "k8s-master-${i + 1}" => {
      ip = cidrhost(var.subnet_cluster_cidr, 11 + i), machine = var.rke2_server.machine_type, tag = "rke2-server", disk_gb = var.boot_disk_gb
    } },
    { for i in range(var.rke2_agent.count) : "k8s-worker-${i + 1}" => {
      # agents hold local-path storage (SeaweedFS/OpenSearch/Ollama) -> larger encrypted boot disk
      ip = cidrhost(var.subnet_cluster_cidr, 21 + i), machine = var.rke2_agent.machine_type, tag = "rke2-agent", disk_gb = var.agent_boot_disk_gb
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
    # CMEK when provided; else Google-managed keys (both encrypt at rest).
    kms_key_self_link = var.disk_kms_key != "" ? var.disk_kms_key : null
    initialize_params {
      image = var.vm_image
      size  = each.value.disk_gb # servers: boot_disk_gb; agents: agent_boot_disk_gb (local-path storage)
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
