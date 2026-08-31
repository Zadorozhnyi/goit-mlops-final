output "mlflow_service" {
  description = "In-cluster DNS name of the MLflow tracking/registry service"
  value       = "mlflow-tracking.${var.target_namespace}.svc.cluster.local:5000"
}

output "mlflow_ui_port_forward" {
  description = "Open the MLflow UI on http://localhost:5000"
  value       = "kubectl port-forward svc/mlflow-tracking -n ${var.target_namespace} 5000:5000"
}

output "pushgateway_service" {
  description = "In-cluster DNS name of the Prometheus Pushgateway"
  value       = "prometheus-pushgateway.${var.monitoring_namespace}.svc.cluster.local:9091"
}
