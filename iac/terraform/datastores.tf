###############################################################################
# Datastore VMs — Mongo / Redis / Kafka / TiDB / MySQL on the private data subnet.
# Static internal IPs (derived from the data subnet), no public IPs.
###############################################################################
locals {
  # 4 DEDICATED Redis Sentinel clusters. Node count per cluster = var.redis.count
  # (TEST = 1 each -> 4 VMs; HA = 3 each -> 12 VMs for Sentinel quorum).
  # base = first host offset in the data subnet for that cluster's nodes.
  redis_cluster_base = { shared = 21, analytics = 24, prometrics = 27, bullmq = 61 }
  redis_nodes = merge([
    for cname, base in local.redis_cluster_base : {
      for i in range(var.redis.count) : "redis-${cname}-${i + 1}" => {
        ip = cidrhost(var.subnet_data_cidr, base + i), machine = var.redis.machine_type, data_disk = 0, role = "redis"
      }
    }
  ]...)

  # Host offsets within the data subnet (e.g. 10.20.10.11 ...).
  datastore_nodes = merge(
    { for i in range(var.mongo.count) : "mongo-${i + 1}" => {
      ip = cidrhost(var.subnet_data_cidr, 11 + i), machine = var.mongo.machine_type, data_disk = var.mongo.data_disk_gb, role = "mongo"
    } },
    local.redis_nodes,
    { for i in range(var.kafka.count) : "kafka-${i + 1}" => {
      ip = cidrhost(var.subnet_data_cidr, 31 + i), machine = var.kafka.machine_type, data_disk = var.kafka.data_disk_gb, role = "kafka"
    } },
    { for i in range(var.mysql.count) : "mysql-${i + 1}" => {
      ip = cidrhost(var.subnet_data_cidr, 41 + i), machine = var.mysql.machine_type, data_disk = var.mysql.data_disk_gb, role = "mysql"
    } },
    { for i in range(var.tidb.count) : "tidb-${i + 1}" => {
      ip = cidrhost(var.subnet_data_cidr, 51 + i), machine = var.tidb.machine_type, data_disk = var.tidb.data_disk_gb, role = "tidb"
    } },
  )
}

resource "google_compute_disk" "datastore_data" {
  for_each = { for k, v in local.datastore_nodes : k => v if v.data_disk > 0 }
  name     = "${var.name_prefix}-${each.key}-data"
  type     = var.disk_type
  zone     = var.zone
  size     = each.value.data_disk
  labels   = var.labels

  # CMEK when provided; else Google-managed keys (both encrypt data at rest).
  dynamic "disk_encryption_key" {
    for_each = var.disk_kms_key != "" ? [1] : []
    content {
      kms_key_self_link = var.disk_kms_key
    }
  }
}

resource "google_compute_instance" "datastore" {
  for_each     = local.datastore_nodes
  name         = "${var.name_prefix}-${each.key}"
  machine_type = each.value.machine
  zone         = var.zone
  tags         = ["datastore", each.value.role]
  labels       = merge(var.labels, { role = each.value.role })

  boot_disk {
    # CMEK when provided; else Google-managed keys (both encrypt at rest).
    kms_key_self_link = var.disk_kms_key != "" ? var.disk_kms_key : null
    initialize_params {
      image = var.vm_image
      size  = var.boot_disk_gb
      type  = var.disk_type
    }
  }

  dynamic "attached_disk" {
    for_each = each.value.data_disk > 0 ? [1] : []
    content {
      source      = google_compute_disk.datastore_data[each.key].id
      device_name = "data"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.data.id
    network_ip = each.value.ip
    # no access_config block => no public IP
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

output "datastore_ips" {
  description = "Internal IPs of all datastore VMs."
  value       = { for k, n in local.datastore_nodes : "${var.name_prefix}-${k}" => n.ip }
}
