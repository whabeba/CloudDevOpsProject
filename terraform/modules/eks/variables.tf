variable "name" {
  description = "Name prefix for IAM resources."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version (null lets AWS/Floci choose)."
  type        = string
  default     = null
}

variable "subnet_ids" {
  description = "Private subnet IDs used by the control plane and node groups."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "EKS requires at least two subnets in different AZs."
  }
}

variable "subnet_azs" {
  description = "Availability zones matching subnet_ids (used for node labels)."
  type        = list(string)
}

variable "node_instance_type" {
  description = "Instance type for the worker nodes."
  type        = string
  default     = "t3.medium"
}

variable "node_ami_type" {
  description = "EKS optimized AMI type."
  type        = string
  default     = "AL2023_x86_64_STANDARD"
}

variable "node_disk_size" {
  description = "Worker node root disk size in GiB."
  type        = number
  default     = 30
}

variable "node_desired_size" {
  description = "Desired worker nodes per node group."
  type        = number
  default     = 1
}

variable "node_min_size" {
  description = "Minimum worker nodes per node group."
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum worker nodes per node group."
  type        = number
  default     = 2
}

variable "attach_managed_policies" {
  description = "Attach the AWS managed EKS/EC2 policies to the created roles."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Common tags applied to every resource."
  type        = map(string)
  default     = {}
}
