output "staging_url_port_forward" {
  description = "Reach the staging inference service on http://localhost:8000"
  value       = "kubectl port-forward -n staging svc/inference 8000:80"
}

output "production_url_port_forward" {
  description = "Reach the production inference service on http://localhost:8000"
  value       = "kubectl port-forward -n production svc/inference 8000:80"
}
