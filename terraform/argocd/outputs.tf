output "argocd_namespace" {
  description = "Namespace Argo CD runs in (doubles as mlops-system)"
  value       = kubernetes_namespace_v1.argocd.metadata[0].name
}

output "argocd_chart_version" {
  description = "Installed argo-cd chart version"
  value       = helm_release.argocd.version
}

output "argocd_app_version" {
  description = "Argo CD version shipped by that chart"
  value       = helm_release.argocd.metadata.app_version
}

output "applicationset_name" {
  description = "ApplicationSet watching the GitOps repository"
  value       = kubernetes_manifest.namespaces_appset.manifest.metadata.name
}

output "gitops_repo" {
  description = "Repository and directory pattern the ApplicationSet tracks"
  value       = "${var.gitops_repo_url} (${var.gitops_repo_branch}, ${var.gitops_directory_pattern})"
}

output "argocd_ui_port_forward" {
  description = "Open the Argo CD UI on http://localhost:8080"
  value       = "kubectl port-forward svc/argocd-server -n ${var.argocd_namespace} 8080:80"
}

output "argocd_admin_password" {
  description = "Read the generated admin password"
  value       = "kubectl -n ${var.argocd_namespace} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}
