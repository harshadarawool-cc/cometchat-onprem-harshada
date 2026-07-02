###############################################################################
# Project / location
###############################################################################
variable "project_id" {
  type        = string
  description = "GCP project ID."
}

variable "region" {
  type        = string
  description = "GCP region."
  default     = "asia-south1"
}

variable "zone" {
  type        = string
  description = "Primary GCP zone for zonal resources (VMs)."
  default     = "asia-south1-a"
}

variable "name_prefix" {
  type        = string
  description = "Prefix applied to all resource names."
  default     = "cometchat"
}

variable "labels" {
  type        = map(string)
  description = "Common labels applied to resources."
  default = {
    project = "cometchat-onprem"
    managed = "terraform"
  }
}

###############################################################################
# Network
###############################################################################
variable "vpc_name" {
  type        = string
  description = "VPC network name."
  default     = "cometchat-vpc"
}

variable "subnet_data_cidr" {
  type        = string
  description = "Subnet for datastore VMs (Mongo/Redis/Kafka/TiDB/MySQL)."
  default     = "10.20.10.0/24"
}

variable "subnet_cluster_cidr" {
  type        = string
  description = "Subnet for RKE2 nodes (servers + agents)."
  default     = "10.20.20.0/24"
}

variable "subnet_edge_cidr" {
  type        = string
  description = "Subnet for edge/management (bastion)."
  default     = "10.20.30.0/24"
}

###############################################################################
# Access control
###############################################################################
# CIDRs allowed to reach the PUBLIC edge load balancer (443/80/websocket).
# Default is open; tighten to the customer's real client ranges in production.
variable "edge_allowed_cidrs" {
  type        = list(string)
  description = "Source CIDRs permitted to reach the public edge LB."
  default     = ["0.0.0.0/0"]
}

# SSH is via IAP only (no public SSH). 35.235.240.0/20 is Google's IAP range.
variable "iap_cidr" {
  type        = string
  description = "Google IAP source range for SSH."
  default     = "35.235.240.0/20"
}

# SSH key used by Ansible (through the IAP tunnel). Provide the PUBLIC key.
variable "ssh_user" {
  type        = string
  description = "Linux user for Ansible/SSH."
  default     = "ansible"
}

variable "ssh_public_key" {
  type        = string
  description = "Public SSH key (contents) added to VM metadata for the ssh_user."
  default     = ""
}

###############################################################################
# Datastore VM sizing
###############################################################################
variable "mongo" {
  type    = object({ count = number, machine_type = string, data_disk_gb = number })
  default = { count = 3, machine_type = "e2-standard-2", data_disk_gb = 50 }
}

variable "redis" {
  # Each of the 4 Sentinel clusters gets its OWN 3 VMs (12 total). machine_type per node.
  type    = object({ count = number, machine_type = string })
  default = { count = 3, machine_type = "e2-small" } # 12 small nodes; bump if clusters need more RAM
}

# Four INDEPENDENT Redis Sentinel clusters, co-located on the 3 redis VMs on
# distinct ports. master_name stays "mymaster" to match the app envs (each
# sentinel set is isolated, so no conflict). This map drives the Ansible redis
# role AND the per-service secret rewrite (which sentinel endpoints each service uses).
variable "redis_clusters" {
  type = map(object({
    data_port     = number
    sentinel_port = number
    master_name   = string
    purpose       = string
    services      = list(string)
  }))
  default = {
    shared = {
      data_port     = 6379
      sentinel_port = 26379
      master_name   = "mymaster"
      purpose       = "lumen + pubsub + webstore + general cache"
      services      = ["chatapi", "websocket", "ai-agent-service", "receipt-updater", "notificationscore-cache"]
    }
    analytics = {
      data_port     = 6379
      sentinel_port = 26379
      master_name   = "mymaster"
      purpose       = "analytics dedicated"
      services      = ["analytics"]
    }
    prometrics = {
      data_port     = 6379
      sentinel_port = 26379
      master_name   = "mymaster"
      purpose       = "pro-metrics dedicated"
      services      = ["pro-metrics"]
    }
    bullmq = {
      data_port     = 6379
      sentinel_port = 26379
      master_name   = "mymaster"
      purpose       = "bullmq delayed jobs dedicated"
      services      = ["notificationscore-bullmq", "notifications-delay-worker"]
    }
  }
}

variable "kafka" {
  type    = object({ count = number, machine_type = string, data_disk_gb = number })
  default = { count = 3, machine_type = "e2-standard-2", data_disk_gb = 100 }
}

variable "tidb" {
  type    = object({ count = number, machine_type = string, data_disk_gb = number })
  default = { count = 1, machine_type = "e2-standard-4", data_disk_gb = 100 }
}

variable "mysql" {
  type    = object({ count = number, machine_type = string, data_disk_gb = number })
  default = { count = 1, machine_type = "e2-standard-2", data_disk_gb = 50 }
}

###############################################################################
# RKE2 sizing
###############################################################################
variable "rke2_server" {
  type    = object({ count = number, machine_type = string })
  default = { count = 1, machine_type = "e2-standard-4" } # set count=3 for HA control plane
}

variable "rke2_agent" {
  type    = object({ count = number, machine_type = string })
  default = { count = 3, machine_type = "e2-standard-8" }
}

variable "bastion_machine_type" {
  type    = string
  default = "e2-small"
}

variable "vm_image" {
  type        = string
  description = "Boot image for all VMs."
  default     = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
}

variable "boot_disk_gb" {
  type    = number
  default = 30
}

# RKE2 AGENT boot disk — larger, because local-path storage (SeaweedFS volumes, OpenSearch,
# Ollama models) lives on the agent's boot disk under /opt/local-path-provisioner. GCP PDs are
# encrypted at rest with Google-managed keys by default, so this is encrypted storage.
variable "agent_boot_disk_gb" {
  type    = number
  default = 100
}

# PD type for boot + data disks.
#  pd-standard      -> DISKS_TOTAL_GB quota (2048, plenty) -- HDD, used now to dodge the SSD cap.
#  pd-balanced/ssd  -> SSD_TOTAL_GB quota (250, maxed by the kept old infra). Switch back here
#                      once SSD quota is raised or the old infra's 240GB is freed.
variable "disk_type" {
  type    = string
  default = "pd-standard"
}
