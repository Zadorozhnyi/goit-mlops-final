# The only link between the two configurations: the EKS cluster reads the
# network layout from the state file the vpc/ configuration wrote.
#
# There is deliberately no root main.tf calling ./vpc and ./eks - bootstrap
# happens as separate `terraform apply` runs per module, documented in
# README.md, exactly like in goit-mlops-hw-05.
#
# The bucket, key and region below must match vpc/backend.tf exactly.

data "terraform_remote_state" "vpc" {
  backend = "s3"

  config = {
    bucket = "mlops-tfstate-goit-121861012741"
    key    = "final/vpc/terraform.tfstate"
    region = "us-east-1"
  }
}

locals {
  vpc_id          = data.terraform_remote_state.vpc.outputs.vpc_id
  public_subnets  = data.terraform_remote_state.vpc.outputs.public_subnets
  private_subnets = data.terraform_remote_state.vpc.outputs.private_subnets
}
