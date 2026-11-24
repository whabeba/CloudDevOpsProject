###############################################################################
# Production environment - real AWS
###############################################################################

module "network" {
  source = "../../modules/network"

  name                 = var.project_name
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs

  tags = var.tags
}

module "ecr" {
  source = "../../modules/ecr"

  repository_names = ["frontend", "auth-service", "roadmap-service"]
  scan_on_push     = true
  max_images       = 30
  force_delete     = false

  tags = var.tags
}

module "server" {
  source = "../../modules/server"

  name                = var.project_name
  vpc_id              = module.network.vpc_id
  subnet_id           = module.network.public_subnet_ids[0]
  ami_id              = data.aws_ami.ubuntu.id
  instance_type       = var.jenkins_instance_type
  root_volume_size    = 50
  ssh_public_key_path = var.ssh_public_key_path
  ssh_cidr_blocks     = var.ssh_cidr_blocks
  jenkins_cidr_blocks = var.jenkins_cidr_blocks

  tags = var.tags
}

module "eks" {
  source = "../../modules/eks"

  name               = var.project_name
  cluster_name       = "${var.project_name}-eks"
  cluster_version    = var.cluster_version
  subnet_ids         = module.network.private_subnet_ids
  subnet_azs         = module.network.private_subnet_azs
  node_instance_type = var.node_instance_type
  node_desired_size  = var.node_desired_size
  node_min_size      = 2
  node_max_size      = 4

  tags = var.tags
}
