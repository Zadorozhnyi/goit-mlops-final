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
  description = "Name of the existing EKS cluster to install Argo CD into"
  type        = string
  default     = "mlops-final-eks"
}

variable "argocd_namespace" {
  description = "Namespace for Argo CD itself. Doubles as the mlops-system namespace: this is where the platform's own control-plane components (ArgoCD, MLflow, MinIO, Postgres) live, per the final project's namespace split (staging/production/mlops-system/monitoring)."
  type        = string
  default     = "mlops-system"
}

variable "argocd_chart_version" {
  description = <<-EOT
    Version of the argo-cd Helm chart from https://argoproj.github.io/argo-helm.
    10.3.3 ships Argo CD v3.5.1. Pinned on purpose: an unpinned chart turns
    every apply into a possible upgrade.
  EOT
  type        = string
  default     = "10.3.3"
}

variable "gitops_repo_url" {
  description = "Git repository the ApplicationSet watches. Public, so Argo CD needs no credentials."
  type        = string
  default     = "https://github.com/Zadorozhnyi/goit-argo.git"
}

variable "gitops_repo_branch" {
  description = "Branch of the GitOps repository to track"
  type        = string
  default     = "main"
}

variable "gitops_directory_pattern" {
  description = <<-EOT
    Directory glob inside the GitOps repo. Every match becomes one Argo CD
    Application, and the directory name doubles as the target namespace.

    Scoped to final/namespace/* on purpose, not namespace/* - the same
    goit-argo repo also holds namespace/infra-tools and namespace/application
    from earlier, already-graded homeworks (hw-07, hw-09). Reusing namespace/*
    here would make the ApplicationSet pick those up too and stand up a
    second, unwanted copy of the old MLflow/MinIO/Postgres stack.
  EOT
  type        = string
  default     = "final/namespace/*"
}
