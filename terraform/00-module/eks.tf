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

  # 공용 인터넷망 접속
  cluster_endpoint_public_access = true

  enable_irsa = true
  enable_cluster_creator_admin_permissions = true
  authentication_mode = "API_AND_CONFIG_MAP"

  cluster_addons = {
    coredns = {}
    kube-proxy = {}
    vpc-cni = {}

    aws-ebs-csi-driver = {
      most_recent = true
      service_account_role_arn = module.ebs_csi_irsa_role.iam_role_arn
    }
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

module "ebs_csi_irsa_role" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${local.cluster_name}-ebs-csi"
  attach_ebs_csi_policy = true

  oidc_providers = {
    ex = {
      provider_arn = module.eks_mod.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

module "lb_role" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0" 

  role_name = "${local.cluster_name}-lb-controller"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn = module.eks_mod.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}

resource "helm_release" "aws_load_balancer_controller" {
  name = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart = "aws-load-balancer-controller"
  namespace = "kube-system"

  set {
    name = "clusterName"
    value = local.cluster_name
  }
  set {
    name = "serviceAccount.create"
    value = "true"
  }
  set {
    name = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }
  set {
    name = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.lb_role.iam_role_arn
  }
}
