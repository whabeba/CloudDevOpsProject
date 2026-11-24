###############################################################################
# Production backend.
# Create the bucket once with terraform/backend (use_local_endpoint = false),
# then update the bucket name here and run `terraform init -migrate-state`.
###############################################################################

terraform {
  backend "s3" {
    bucket       = "ivolve-terraform-state-prod"
    key          = "prod/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
