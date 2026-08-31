data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = "${var.project}-vpc"
  cidr = var.vpc_cidr

  azs             = local.azs
  public_subnets  = slice(var.public_subnet_cidrs, 0, var.az_count)
  private_subnets = slice(var.private_subnet_cidrs, 0, var.az_count)

  # Worker nodes live in the private subnets and reach the internet through NAT.
  enable_nat_gateway = true
  single_nat_gateway = var.single_nat_gateway

  # Required by EKS: nodes resolve the cluster endpoint by DNS name.
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Tags EKS uses to discover where to place load balancers.
  public_subnet_tags = {
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  tags = {
    Name = "${var.project}-vpc"
  }
}
