variable "project_name" {
  description = "Name prefix for every resource."
  type        = string
  default     = "ivolve"
}

variable "aws_region" {
  description = "AWS region used by the emulator."
  type        = string
  default     = "us-east-1"
}

variable "aws_endpoint" {
  description = "Floci endpoint."
  type        = string
  default     = "http://localhost:4566"
}

variable "access_key" {
  description = "Dummy access key for Floci."
  type        = string
  default     = "test"
}

variable "secret_key" {
  description = "Dummy secret key for Floci."
  type        = string
  default     = "test"
}

variable "vpc_cidr" {
  description = "VPC CIDR."
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Two AZs for the public/private subnets."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs."
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "jenkins_ami_id" {
  description = "Floci AMI alias for Ubuntu 24.04."
  type        = string
  default     = "ami-ubuntu2404-amd64"
}

variable "jenkins_instance_type" {
  description = "Instance type for the Jenkins server."
  type        = string
  default     = "t3.medium"
}

variable "ssh_public_key_path" {
  description = "SSH public key injected into the Jenkins instance."
  type        = string
}

variable "create_iam_instance_profile" {
  description = "Attach an ECR-capable IAM instance profile to Jenkins."
  type        = bool
  default     = true
}

variable "cluster_version" {
  description = "EKS version (null = emulator default)."
  type        = string
  default     = null
}

variable "node_instance_type" {
  description = "EKS worker instance type."
  type        = string
  default     = "t3.medium"
}

variable "tags" {
  description = "Common tags."
  type        = map(string)
  default = {
    Project     = "CloudDevOpsProject"
    Environment = "local"
    ManagedBy   = "terraform"
  }
}
