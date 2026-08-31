terraform {
  backend "s3" {
    bucket = "mlops-tfstate-goit-121861012741"
    key    = "final/eks/terraform.tfstate"
    region = "us-east-1"

    use_lockfile = true
    encrypt      = true
  }
}
