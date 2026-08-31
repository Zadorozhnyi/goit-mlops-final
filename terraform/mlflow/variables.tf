variable "region" {
  description = "AWS region holding the EKS cluster"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name, used in tags"
  type        = string
  default     = "mlops-final"
}

variable "environment" {
  description = "Environment name, used in tags"
  type        = string
  default     = "dev"
}

variable "cluster_name" {
  description = "Name of the existing EKS cluster"
  type        = string
  default     = "mlops-final-eks"
}

variable "argocd_namespace" {
  description = <<-EOT
    Namespace Argo CD runs in. Application CRs in this module are created
    here (not in target_namespace) because Argo CD's controller only watches
    Applications in its own namespace by default - the same convention
    goit-argo/namespace/infra-tools already relied on. spec.destination
    inside each manifest still controls where the actual Helm release lands.
  EOT
  type        = string
  default     = "mlops-system"
}

variable "target_namespace" {
  description = "Namespace the MLflow/MinIO/PostgreSQL workloads are deployed into"
  type        = string
  default     = "mlops-system"
}

variable "monitoring_namespace" {
  description = "Namespace the Pushgateway is deployed into (scraped by the monitoring/ module's Prometheus)"
  type        = string
  default     = "monitoring"
}
