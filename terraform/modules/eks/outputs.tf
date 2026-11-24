output "cluster_name" {
  description = "EKS cluster name."
  value       = aws_eks_cluster.this.name
}

output "cluster_arn" {
  description = "EKS cluster ARN."
  value       = aws_eks_cluster.this.arn
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 CA data for the cluster."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_security_group_id" {
  description = "Security group created by EKS for the control plane."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "node_group_names" {
  description = "Managed node group names."
  value       = aws_eks_node_group.workers[*].node_group_name
}

output "cluster_role_arn" {
  description = "IAM role ARN used by the control plane."
  value       = aws_iam_role.cluster.arn
}

output "node_role_arn" {
  description = "IAM role ARN used by the worker nodes."
  value       = aws_iam_role.node.arn
}
