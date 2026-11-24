output "instance_id" {
  description = "Jenkins EC2 instance ID."
  value       = aws_instance.jenkins.id
}

output "public_ip" {
  description = "Public IP of the Jenkins instance."
  value       = aws_instance.jenkins.public_ip
}

output "private_ip" {
  description = "Private IP of the Jenkins instance."
  value       = aws_instance.jenkins.private_ip
}

output "security_group_id" {
  description = "Jenkins security group ID."
  value       = aws_security_group.jenkins.id
}

output "key_name" {
  description = "SSH key pair name."
  value       = aws_key_pair.jenkins.key_name
}

output "iam_instance_profile" {
  description = "Instance profile attached to Jenkins (empty when disabled)."
  value       = var.create_iam_instance_profile ? aws_iam_instance_profile.jenkins[0].name : ""
}
