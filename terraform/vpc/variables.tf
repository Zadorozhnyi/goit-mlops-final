variable "region" {
  description = "AWS region for every resource in this configuration"
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

variable "vpc_cidr" {
  description = "CIDR block of the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "How many availability zones to spread the subnets across"
  type        = number
  default     = 3

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 4
    error_message = "EKS needs at least two availability zones; more than four is wasteful here."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the public subnets, one per availability zone"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for the private subnets, one per availability zone"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "cluster_name" {
  description = "Name of the EKS cluster the subnets are tagged for. Must match the name used in the eks/ configuration."
  type        = string
  default     = "mlops-final-eks"
}

variable "single_nat_gateway" {
  description = "Route all private subnets through one NAT gateway. Keep true: one NAT per AZ triples the cost for no benefit in a study project."
  type        = bool
  default     = true
}
