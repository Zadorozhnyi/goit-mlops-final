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
  description = "Namespace Argo CD runs in - Application CRs are created here, same convention as mlflow/ and argocd/ modules"
  type        = string
  default     = "mlops-system"
}

variable "target_namespace" {
  description = "Namespace Prometheus/Grafana/Alertmanager/Loki/Promtail are deployed into"
  type        = string
  default     = "monitoring"
}
