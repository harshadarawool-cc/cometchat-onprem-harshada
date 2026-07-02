output "vpc_name" {
  value = google_compute_network.vpc.name
}

output "subnets" {
  value = {
    data    = google_compute_subnetwork.data.ip_cidr_range
    cluster = google_compute_subnetwork.cluster.ip_cidr_range
    edge    = google_compute_subnetwork.edge.ip_cidr_range
  }
}

output "redis_clusters" {
  description = "The 4 independent Redis Sentinel clusters (ports + attached services)."
  value       = var.redis_clusters
}

# VM IP outputs are added in datastores.tf / rke2.tf as those resources land.
