###############################################################################
# Terraform state backend bootstrap
#
# Creates the S3 bucket used by the S3 remote backend. Run this once with local
# state before initialising any environment:
#
#   cd terraform/backend
#   terraform init
#   terraform apply
#
# The same configuration works against AWS and against Floci (local lab).
###############################################################################

terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

provider "aws" {
  region                      = var.aws_region
  access_key                  = var.access_key
  secret_key                  = var.secret_key
  skip_credentials_validation = var.use_local_endpoint
  skip_metadata_api_check     = var.use_local_endpoint
  skip_requesting_account_id  = var.use_local_endpoint
  s3_use_path_style           = var.use_local_endpoint

  dynamic "endpoints" {
    for_each = var.use_local_endpoint ? [1] : []

    content {
      ec2      = var.aws_endpoint
      eks      = var.aws_endpoint
      ecr      = var.aws_endpoint
      iam      = var.aws_endpoint
      sts      = var.aws_endpoint
      s3       = var.aws_endpoint
      dynamodb = var.aws_endpoint
    }
  }
}

resource "aws_s3_bucket" "state" {
  bucket        = var.state_bucket_name
  force_destroy = var.force_destroy

  tags = merge(var.tags, { Name = var.state_bucket_name })
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
