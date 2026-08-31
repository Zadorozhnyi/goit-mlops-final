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
  description = "Namespace Argo CD runs in - Application CRs are created here, same convention as mlflow/ and monitoring/ modules"
  type        = string
  default     = "mlops-system"
}

variable "inference_repo_url" {
  description = "Git repo holding the inference Helm chart (this same project's repo)"
  type        = string
  default     = "https://github.com/Zadorozhnyi/goit-mlops-final.git"
}

variable "inference_repo_branch" {
  description = "Branch to deploy the inference chart from"
  type        = string
  default     = "master"
}
