locals {
  cluster_name = "eks-mod"
}

module "eks_mod" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name = local.cluster_name
  cluster_version = "1.29"

  vpc_id = module.vpc_mod.vpc_id
  subnet_ids = module.vpc_mod.private_subnets

  cluster_endpoint_public_access = true

  cluster_addons = {
    coredns = {}
    kube-proxy = {}
    vpc-cni = {}
  }

  eks_managed_node_groups = {
    default = {
      instance_types = ["t3.small"]

      desired_size = 2
      min_size = 1
      max_size = 3

      subnet_ids = module.vpc_mod.private_subnets
    }
  }

  tags = {
    project = "eks-mod"
  }
}

