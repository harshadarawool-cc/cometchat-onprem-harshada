###############################################################################
# Firewall — GCP denies all ingress by default. We open only what's needed.
# Network tags: "datastore", "rke2-server", "rke2-agent", "bastion".
###############################################################################

# East-west: allow ALL traffic between VMs inside the VPC private ranges.
# Single-tenant private cluster -> trust intra-VPC. Covers datastore ports
# (Mongo 27017, Redis 6379-6382 + Sentinel 26379-26382, Kafka 9092/9093,
# TiDB 3306/2379/2380/20160, MySQL 3306) and all RKE2 node-to-node ports.
resource "google_compute_firewall" "internal" {
  name      = "${var.name_prefix}-allow-internal"
  network   = google_compute_network.vpc.id
  direction = "INGRESS"
  priority  = 1000

  source_ranges = [
    var.subnet_data_cidr,
    var.subnet_cluster_cidr,
    var.subnet_edge_cidr,
  ]

  allow { protocol = "tcp" }
  allow { protocol = "udp" }
  allow { protocol = "icmp" }
}

# SSH only via Google IAP (no public SSH on any VM).
resource "google_compute_firewall" "iap_ssh" {
  name          = "${var.name_prefix}-allow-iap-ssh"
  network       = google_compute_network.vpc.id
  direction     = "INGRESS"
  priority      = 1000
  source_ranges = [var.iap_cidr]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

# IAP -> RKE2 API server (so kubectl works over an IAP tunnel to the control plane).
resource "google_compute_firewall" "iap_k8s_api" {
  name          = "${var.name_prefix}-allow-iap-k8s-api"
  network       = google_compute_network.vpc.id
  direction     = "INGRESS"
  priority      = 1000
  source_ranges = [var.iap_cidr]
  target_tags   = ["rke2-server"]

  allow {
    protocol = "tcp"
    ports    = ["6443"]
  }
}

# GCP load-balancer health checks -> ingress nodes.
resource "google_compute_firewall" "health_checks" {
  name          = "${var.name_prefix}-allow-health-checks"
  network       = google_compute_network.vpc.id
  direction     = "INGRESS"
  priority      = 1000
  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
  target_tags   = ["rke2-agent"]

  # 443 only — cert-manager uses Route53 DNS-01 (no HTTP-01), so no public :80 needed.
  allow {
    protocol = "tcp"
    ports    = ["443"]
  }
}

# Public edge: clients -> ingress-nginx (hostPort 443) on the agent nodes.
# Tighten edge_allowed_cidrs to the customer's real client ranges in production.
resource "google_compute_firewall" "edge_ingress" {
  name          = "${var.name_prefix}-allow-edge-ingress"
  network       = google_compute_network.vpc.id
  direction     = "INGRESS"
  priority      = 1000
  source_ranges = var.edge_allowed_cidrs
  target_tags   = ["rke2-agent"]

  # INBOUND-CLOSED: HTTPS only at the front door (no public :80).
  allow {
    protocol = "tcp"
    ports    = ["443"]
  }
}

###############################################################################
# EGRESS — left at GCP default (allow-all) during bootstrap so nodes can pull
# from ECR + OS package repos + get.rke2.io. AFTER the cluster is up, switch to
# default-deny + an allowlist (per the data-residency egress decision). The
# locked-down version is below, commented; enable it post-bootstrap.
###############################################################################
# resource "google_compute_firewall" "egress_deny_all" {
#   name               = "${var.name_prefix}-deny-egress-all"
#   network            = google_compute_network.vpc.id
#   direction          = "EGRESS"
#   priority           = 65534
#   destination_ranges = ["0.0.0.0/0"]
#   deny { protocol = "all" }
# }
# resource "google_compute_firewall" "egress_allow_internal" {
#   name               = "${var.name_prefix}-allow-egress-internal"
#   network            = google_compute_network.vpc.id
#   direction          = "EGRESS"
#   priority           = 1000
#   destination_ranges = [var.subnet_data_cidr, var.subnet_cluster_cidr, var.subnet_edge_cidr]
#   allow { protocol = "all" }
# }
# # + explicit allow rules for ECR ranges / approved external hosts (recordings/rtc/composio if tested).
