output "grafana_port_forward" {
  description = "Open the Grafana UI on http://localhost:3000 (admin / prom-operator)"
  value       = "kubectl port-forward -n ${var.target_namespace} svc/prometheus-operator-grafana 3000:80"
}

output "prometheus_port_forward" {
  description = "Open the Prometheus UI on http://localhost:9090"
  value       = "kubectl port-forward -n ${var.target_namespace} svc/prometheus-operator-prometheus 9090:9090"
}

output "loki_service" {
  description = "In-cluster DNS name of the Loki service (queried from Grafana Explore)"
  value       = "loki.${var.target_namespace}.svc.cluster.local:3100"
}
