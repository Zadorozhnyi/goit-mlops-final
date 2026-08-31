variable "region" {
  description = "AWS region. Must match the region of the VPC state and of vpc/variables.tf."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name, used as a prefix for resource names and tags"
  type        = string
  default     = "mlops-final"
}

variable "environment" {
  description = "Environment name, used in tags"
  type        = string
  default     = "dev"
}

variable "cluster_name" {
  description = "Name of the EKS cluster. Must match cluster_name in vpc/variables.tf so the subnet tags line up."
  type        = string
  default     = "mlops-final-eks"
}

variable "kubernetes_version" {
  description = <<-EOT
    Kubernetes version for the control plane. Keep this on a version in
    STANDARD support: extended support costs $0.60/hour instead of $0.10.
    Check with: aws eks describe-cluster-versions
  EOT
  type        = string
  default     = "1.35"
}

variable "endpoint_public_access" {
  description = "Expose the API server publicly so kubectl works from a workstation without a VPN"
  type        = bool
  default     = true
}

variable "cpu_node_group" {
  description = <<-EOT
    Size and instance types of the general-purpose node group. This one pool
    hosts every namespace (staging, production, mlops-system, monitoring) -
    they are logical Kubernetes namespaces inside one cluster, not separate
    infrastructure, so a single node group is enough as long as it is sized
    for the combined workload.

    t3.small rather than the more natural t3.medium: this AWS account is
    restricted to the Free Tier, and EC2 rejects anything outside that list
    with "InvalidParameterCombination - The specified instance type is not
    eligible for Free Tier". The allowed set in us-east-1 is t3.micro,
    t3.small, t4g.micro, t4g.small, c7i-flex.large and m7i-flex.large.
    Check before changing:
      aws ec2 describe-instance-types --filters Name=free-tier-eligible,Values=true

    Lesson from goit-mlops-hw-05/hw-09: t3.small caps at 11 pods/node (ENI
    limit) and ~1.4Gi allocatable memory/node. ArgoCD + kube-prometheus-stack
    + mlflow/minio/postgres alone needed 4 nodes; adding a staging AND a
    production copy of the inference service (blue-green) will need
    re-checking this number once the workloads are known, and possibly a
    vCPU quota increase (account default is 8 on-demand vCPUs for t3-family).
  EOT
  type = object({
    instance_types = list(string)
    min_size       = number
    max_size       = number
    desired_size   = number
  })
  default = {
    instance_types = ["t3.small"]
    min_size       = 1
    max_size       = 6
    desired_size   = 4
  }
}
