###############################################################################
# Local environment - runs against Floci (AWS local emulator) on :4566
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
  force_delete     = true

  tags = var.tags
}

module "server" {
  source = "../../modules/server"

  name                        = var.project_name
  vpc_id                      = module.network.vpc_id
  subnet_id                   = module.network.public_subnet_ids[0]
  ami_id                      = var.jenkins_ami_id
  instance_type               = var.jenkins_instance_type
  ssh_public_key_path         = var.ssh_public_key_path
  create_iam_instance_profile = var.create_iam_instance_profile

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
  node_desired_size  = 1
  node_min_size      = 1
  node_max_size      = 2

  tags = var.tags
}
