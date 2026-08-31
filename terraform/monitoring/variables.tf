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

variable "drift_check_image" {
  description = "ECR image (without tag) for the Block E1 drift-check CronJob, see monitoring/drift/"
  type        = string
  default     = "121861012741.dkr.ecr.us-east-1.amazonaws.com/mlops-final/drift-check"
}
