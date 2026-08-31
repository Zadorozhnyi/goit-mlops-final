terraform {
  backend "s3" {
    bucket = "mlops-tfstate-goit-121861012741"
    key    = "final/vpc/terraform.tfstate"
    region = "us-east-1"

    # Native S3 state locking (Terraform >= 1.10) - no DynamoDB table needed.
    use_lockfile = true
    encrypt      = true
  }
}
