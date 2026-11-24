variable "name" {
  description = "Name prefix for all resources."
  type        = string
}

variable "vpc_id" {
  description = "VPC the Jenkins instance lives in."
  type        = string
}

variable "subnet_id" {
  description = "Public subnet for the Jenkins instance."
  type        = string
}

variable "ami_id" {
  description = "Ubuntu AMI to launch (local Floci alias or a real AMI ID)."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for Jenkins."
  type        = string
  default     = "t3.medium"
}

variable "root_volume_size" {
  description = "Root EBS volume size in GiB."
  type        = number
  default     = 30
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key injected into the instance."
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "ssh_cidr_blocks" {
  description = "CIDRs allowed to reach SSH."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "jenkins_cidr_blocks" {
  description = "CIDRs allowed to reach the Jenkins UI."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "jenkins_admin_user" {
  description = "Linux user created for Jenkins administration."
  type        = string
  default     = "jenkins"
}

variable "create_iam_instance_profile" {
  description = "Create an IAM instance profile that can push to ECR."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Common tags applied to every resource."
  type        = map(string)
  default     = {}
}
