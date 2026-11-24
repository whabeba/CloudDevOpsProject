provider "aws" {
  region                      = var.aws_region
  access_key                  = var.access_key
  secret_key                  = var.secret_key
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true

  endpoints {
    ec2         = var.aws_endpoint
    eks         = var.aws_endpoint
    ecr         = var.aws_endpoint
    iam         = var.aws_endpoint
    sts         = var.aws_endpoint
    s3          = var.aws_endpoint
    dynamodb    = var.aws_endpoint
    autoscaling = var.aws_endpoint
    cloudwatch  = var.aws_endpoint
    logs        = var.aws_endpoint
  }

  default_tags {
    tags = var.tags
  }
}
