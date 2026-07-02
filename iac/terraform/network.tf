###############################################################################
# VPC + private subnets
###############################################################################
resource "google_compute_network" "vpc" {
  name                            = var.vpc_name
  auto_create_subnetworks         = false
  routing_mode                    = "REGIONAL"
  delete_default_routes_on_create = false
}

resource "google_compute_subnetwork" "data" {
  name                     = "${var.name_prefix}-data"
  ip_cidr_range            = var.subnet_data_cidr
  region                   = var.region
  network                  = google_compute_network.vpc.id
  private_ip_google_access = true
}

resource "google_compute_subnetwork" "cluster" {
  name                     = "${var.name_prefix}-cluster"
  ip_cidr_range            = var.subnet_cluster_cidr
  region                   = var.region
  network                  = google_compute_network.vpc.id
  private_ip_google_access = true
}

resource "google_compute_subnetwork" "edge" {
  name                     = "${var.name_prefix}-edge"
  ip_cidr_range            = var.subnet_edge_cidr
  region                   = var.region
  network                  = google_compute_network.vpc.id
  private_ip_google_access = true
}

###############################################################################
# Cloud NAT — controlled outbound egress (no VM has a public IP).
# Needed so nodes can pull images (ECR) and OS packages during bootstrap.
# Egress is further restricted by firewall (see firewall.tf) for data-residency.
###############################################################################
resource "google_compute_router" "router" {
  name    = "${var.name_prefix}-router"
  region  = var.region
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat" {
  name                               = "${var.name_prefix}-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}
