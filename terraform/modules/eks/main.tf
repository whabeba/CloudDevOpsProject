###############################################################################
# EKS Module
# Control plane in the private subnets + two managed node groups, one per
# private subnet / availability zone (2 worker nodes in total).
###############################################################################

locals {
  tags = merge(var.tags, { Module = "eks" })
}

###############################################################################
# IAM - cluster role
###############################################################################

data "aws_iam_policy_document" "eks_assume_role" {
  statement {
    effect = "Allow"

    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${var.name}-eks-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.eks_assume_role.json

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "cluster_policies" {
  for_each = var.attach_managed_policies ? toset([
    "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy",
    "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController",
  ]) : toset([])

  role       = aws_iam_role.cluster.name
  policy_arn = each.value
}

###############################################################################
# IAM - worker node role
###############################################################################

data "aws_iam_policy_document" "node_assume_role" {
  statement {
    effect = "Allow"

    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${var.name}-eks-node-role"
  assume_role_policy = data.aws_iam_policy_document.node_assume_role.json

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "node_policies" {
  for_each = var.attach_managed_policies ? toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
  ]) : toset([])

  role       = aws_iam_role.node.name
  policy_arn = each.value
}

###############################################################################
# EKS cluster
###############################################################################

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.cluster_version

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  tags = merge(local.tags, { Name = var.cluster_name })

  depends_on = [aws_iam_role_policy_attachment.cluster_policies]
}

###############################################################################
# Managed node groups - one per private subnet / AZ
###############################################################################

resource "aws_eks_node_group" "workers" {
  count = length(var.subnet_ids)

  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.cluster_name}-ng-${count.index + 1}"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = [var.subnet_ids[count.index]]

  instance_types = [var.node_instance_type]
  ami_type       = var.node_ami_type
  capacity_type  = "ON_DEMAND"
  disk_size      = var.node_disk_size

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    role = "worker"
    az   = var.subnet_azs[count.index]
  }

  tags = merge(local.tags, {
    Name                                        = "${var.cluster_name}-ng-${count.index + 1}"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  })

  depends_on = [aws_iam_role_policy_attachment.node_policies]
}
