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

# Public edge: clients -> HAProxy VMs on :443 (TLS SNI passthrough).
# HAProxy is the ONLY public entry point (replaces the old GCP L4 LB). Tighten
# edge_allowed_cidrs to the customer's real client/VPN ranges in production.
resource "google_compute_firewall" "edge_haproxy" {
  name          = "${var.name_prefix}-allow-edge-haproxy"
  network       = google_compute_network.vpc.id
  direction     = "INGRESS"
  priority      = 1000
  source_ranges = var.edge_allowed_cidrs
  target_tags   = ["haproxy"]

  # INBOUND-CLOSED: HTTPS only at the front door (SNI passthrough on :443).
  allow {
    protocol = "tcp"
    ports    = ["443"]
  }
}

# IAP -> HAProxy stats page (:8404) for edge health/observability (admin only).
resource "google_compute_firewall" "iap_haproxy_stats" {
  name          = "${var.name_prefix}-allow-iap-haproxy-stats"
  network       = google_compute_network.vpc.id
  direction     = "INGRESS"
  priority      = 1000
  source_ranges = [var.iap_cidr]
  target_tags   = ["haproxy"]

  allow {
    protocol = "tcp"
    ports    = ["8404"]
  }
}

# HAProxy -> RKE2 agents on the Kubernetes NodePort range. HAProxy forwards each
# SNI-matched connection to the per-service NodePort where the pod's nginx TLS
# sidecar terminates the wildcard cert. The blanket "internal" rule above already
# covers edge->cluster, but this explicit rule documents the path and survives any
# future tightening of the internal rule.
resource "google_compute_firewall" "haproxy_to_nodeports" {
  name          = "${var.name_prefix}-allow-haproxy-nodeports"
  network       = google_compute_network.vpc.id
  direction     = "INGRESS"
  priority      = 1000
  source_ranges = [var.subnet_edge_cidr] # the edge subnet (where HAProxy lives)
  target_tags   = ["rke2-agent"]

  allow {
    protocol = "tcp"
    ports    = ["30000-32767"]
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
