output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_version" {
  description = "Kubernetes version running on the control plane"
  value       = module.eks.cluster_version
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the cluster control plane"
  value       = module.eks.cluster_security_group_id
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded CA certificate of the cluster"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "node_groups" {
  description = "Managed node groups created for this cluster"
  value       = keys(module.eks.eks_managed_node_groups)
}

output "vpc_id_from_remote_state" {
  description = "VPC ID read from the vpc/ state - proves terraform_remote_state resolved"
  value       = local.vpc_id
}

output "configure_kubectl" {
  description = "Command that points kubectl at this cluster"
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}
