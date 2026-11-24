variable "repository_names" {
  description = "ECR repository names (one per microservice)."
  type        = list(string)
  default     = ["frontend", "auth-service", "roadmap-service"]
}

variable "image_tag_mutability" {
  description = "IMMUTABLE or MUTABLE tags."
  type        = string
  default     = "MUTABLE"

  validation {
    condition     = contains(["IMMUTABLE", "MUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be IMMUTABLE or MUTABLE."
  }
}

variable "scan_on_push" {
  description = "Scan images for vulnerabilities when pushed."
  type        = bool
  default     = true
}

variable "max_images" {
  description = "Number of images kept per repository."
  type        = number
  default     = 10
}

variable "force_delete" {
  description = "Allow deleting a non-empty repository (useful for local labs)."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Common tags applied to every resource."
  type        = map(string)
  default     = {}
}
