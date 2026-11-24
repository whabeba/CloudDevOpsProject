output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets."
  value       = aws_subnet.private[*].id
}

output "public_subnet_azs" {
  description = "AZs of the public subnets."
  value       = aws_subnet.public[*].availability_zone
}

output "private_subnet_azs" {
  description = "AZs of the private subnets."
  value       = aws_subnet.private[*].availability_zone
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway."
  value       = aws_internet_gateway.this.id
}

output "nat_gateway_id" {
  description = "ID of the NAT Gateway."
  value       = aws_nat_gateway.this.id
}

output "public_network_acl_id" {
  description = "ID of the public Network ACL."
  value       = aws_network_acl.public.id
}

output "private_network_acl_id" {
  description = "ID of the private Network ACL."
  value       = aws_network_acl.private.id
}
