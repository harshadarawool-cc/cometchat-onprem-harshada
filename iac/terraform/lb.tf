###############################################################################
# Edge load balancer — the ONE public entry point.
# External passthrough Network LB (regional, TCP) -> ingress-nginx (hostPort
# 80/443) on the RKE2 agent nodes. Internal services stay ClusterIP.
###############################################################################
resource "google_compute_address" "edge" {
  name         = "${var.name_prefix}-edge-ip"
  region       = var.region
  address_type = "EXTERNAL"
}

# Unmanaged instance group of the agent nodes (where ingress-nginx runs).
resource "google_compute_instance_group" "agents" {
  name      = "${var.name_prefix}-agents"
  zone      = var.zone
  instances = [for k, inst in google_compute_instance.rke2 : inst.self_link if startswith(k, "k8s-worker-")]

  named_port {
    name = "http"
    port = 80
  }
  named_port {
    name = "https"
    port = 443
  }
}

resource "google_compute_region_health_check" "edge" {
  name   = "${var.name_prefix}-edge-hc"
  region = var.region

  tcp_health_check {
    port = 443
  }
}

resource "google_compute_region_backend_service" "edge" {
  name                  = "${var.name_prefix}-edge-bes"
  region                = var.region
  load_balancing_scheme = "EXTERNAL"
  protocol              = "TCP"
  health_checks         = [google_compute_region_health_check.edge.id]

  backend {
    group          = google_compute_instance_group.agents.self_link
    balancing_mode = "CONNECTION"
  }
}

resource "google_compute_forwarding_rule" "edge" {
  name                  = "${var.name_prefix}-edge-fr"
  region                = var.region
  load_balancing_scheme = "EXTERNAL"
  ip_address            = google_compute_address.edge.address
  ip_protocol           = "TCP"
  ports                 = ["443"]
  backend_service       = google_compute_region_backend_service.edge.id
}

output "edge_lb_ip" {
  description = "Public IP of the edge load balancer — point your DNS / /etc/hosts here."
  value       = google_compute_address.edge.address
}
