variable "project_name" {
  description = "Name prefix for every resource."
  type        = string
  default     = "ivolve"
}

variable "aws_region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
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

variable "jenkins_instance_type" {
  description = "Instance type for the Jenkins server."
  type        = string
  default     = "t3.medium"
}

variable "ssh_public_key_path" {
  description = "SSH public key injected into the Jenkins instance."
  type        = string
}

variable "ssh_cidr_blocks" {
  description = "CIDRs allowed to reach SSH (restrict this in production)."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "jenkins_cidr_blocks" {
  description = "CIDRs allowed to reach the Jenkins UI."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "cluster_version" {
  description = "EKS Kubernetes version."
  type        = string
  default     = "1.31"
}

variable "node_instance_type" {
  description = "EKS worker instance type."
  type        = string
  default     = "t3.medium"
}

variable "node_desired_size" {
  description = "Desired worker nodes per node group."
  type        = number
  default     = 1
}

variable "tags" {
  description = "Common tags."
  type        = map(string)
  default = {
    Project     = "CloudDevOpsProject"
    Environment = "prod"
    ManagedBy   = "terraform"
  }
}
