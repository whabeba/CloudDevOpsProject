variable "aws_region" {
  description = "AWS region for the state bucket."
  type        = string
  default     = "us-east-1"
}

variable "state_bucket_name" {
  description = "Globally unique S3 bucket name for Terraform state."
  type        = string
  default     = "ivolve-terraform-state"
}

variable "use_local_endpoint" {
  description = "Point the AWS provider at the local emulator (Floci)."
  type        = bool
  default     = false
}

variable "aws_endpoint" {
  description = "Local AWS emulator endpoint."
  type        = string
  default     = "http://localhost:4566"
}

variable "access_key" {
  description = "Access key (dummy value for Floci)."
  type        = string
  default     = "test"
}

variable "secret_key" {
  description = "Secret key (dummy value for Floci)."
  type        = string
  default     = "test"
}

variable "force_destroy" {
  description = "Allow destroying a non-empty state bucket (local labs only)."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Common tags."
  type        = map(string)
  default     = { Project = "CloudDevOpsProject" }
}
