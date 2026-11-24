###############################################################################
# Server Module
# Jenkins EC2 instance + security group + optional IAM instance profile
###############################################################################

locals {
  tags = merge(var.tags, { Module = "server" })
}

###############################################################################
# Security group
###############################################################################

resource "aws_security_group" "jenkins" {
  name        = "${var.name}-jenkins-sg"
  description = "Jenkins EC2 access (SSH + UI)"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH for Ansible"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_cidr_blocks
  }

  ingress {
    description = "Jenkins web UI"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = var.jenkins_cidr_blocks
  }

  ingress {
    description = "HTTP (Jenkins behind a proxy / ingress)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.jenkins_cidr_blocks
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${var.name}-jenkins-sg" })
}

###############################################################################
# SSH key pair
###############################################################################

resource "aws_key_pair" "jenkins" {
  key_name   = "${var.name}-jenkins-key"
  public_key = file(var.ssh_public_key_path)

  tags = merge(local.tags, { Name = "${var.name}-jenkins-key" })
}

###############################################################################
# IAM: allow the instance to push/pull images to ECR
###############################################################################

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect = "Allow"

    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "jenkins" {
  count = var.create_iam_instance_profile ? 1 : 0

  name               = "${var.name}-jenkins-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "jenkins_ecr" {
  count = var.create_iam_instance_profile ? 1 : 0

  role       = aws_iam_role.jenkins[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}

resource "aws_iam_instance_profile" "jenkins" {
  count = var.create_iam_instance_profile ? 1 : 0

  name = "${var.name}-jenkins-instance-profile"
  role = aws_iam_role.jenkins[0].name
}

###############################################################################
# EC2 instance
###############################################################################

resource "aws_instance" "jenkins" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  key_name                    = aws_key_pair.jenkins.key_name
  vpc_security_group_ids      = [aws_security_group.jenkins.id]
  associate_public_ip_address = true
  iam_instance_profile        = var.create_iam_instance_profile ? aws_iam_instance_profile.jenkins[0].name : null

  user_data = templatefile("${path.module}/templates/user_data.sh.tftpl", {
    jenkins_admin_user = var.jenkins_admin_user
  })

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = merge(local.tags, { Name = "${var.name}-jenkins" })
}
