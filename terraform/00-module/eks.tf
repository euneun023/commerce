locals {
  cluster_name = "eks-mod"
}

module "eks_mod" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = local.cluster_name
  cluster_version = "1.31"

  vpc_id     = module.vpc_mod.vpc_id
  subnet_ids = module.vpc_mod.private_subnets

  # 공용 인터넷망 접속
  cluster_endpoint_public_access = true
  cluster_endpoint_private_access = true
  enable_irsa                              = true
  enable_cluster_creator_admin_permissions = true
  authentication_mode                      = "API_AND_CONFIG_MAP"


  node_security_group_tags = {
    "karpenter.sh/discovery" = local.cluster_name
  }

  cluster_addons = {
    coredns    = {}
    kube-proxy = {}
    vpc-cni    = {
      most_recent = true
      configuration_values = jsonencode({
        env = {
            ENABLE_PREFIX_DELEGATION = "true"
	    WARM_PREFIX_TARGET = "1"
          }
      })

    }

    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.ebs_csi_irsa_role.iam_role_arn
    }
  }

  eks_managed_node_groups = {
    default = {
      instance_types = ["t3.small"]
      ami_type       = "AL2_x86_64"
      capacity_type  = "SPOT"

      iam_role_additional_policies = {
        AmazonEC2ContainerRegistryReadOnly = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
      }

      desired_size = 4
      min_size     = 2
      max_size     = 5

      subnet_ids = module.vpc_mod.private_subnets
    }
  }

  tags = {
    project = "eks-mod"
  }
}

module "ebs_csi_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name             = "${local.cluster_name}-ebs-csi"
  attach_ebs_csi_policy = true

  oidc_providers = {
    ex = {
      provider_arn               = module.eks_mod.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

module "lb_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name                              = "${local.cluster_name}-lb-controller"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks_mod.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"

  wait    = true
  timeout = 600

  set = [
    {
      name  = "clusterName"
      value = local.cluster_name
    },
    {
      name  = "serviceAccount.create"
      value = "true"
    },
    {
      name  = "serviceAccount.name"
      value = "aws-load-balancer-controller"
    },
    {
      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = module.lb_role.iam_role_arn
    }
  ]
}

resource "kubernetes_storage_class_v1" "gp3" {
  metadata {
    name = "gp3"
  }
  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  allow_volume_expansion = true
  volume_binding_mode    = "WaitForFirstConsumer"
  parameters = {
    type = "gp3"
  }
  depends_on = [module.eks_mod]
}

resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  namespace  = "kube-system"
  version    = "3.12.2"

  wait    = true
  timeout = 600

  set = [
    {
      name  = "args[0]"
      value = "--kubelet-insecure-tls"
    },
    {
      name  = "args[1]"
      value = "--kubelet-preferred-address-types=InternalIP\\,Hostname\\,ExternalIP"
    }
  ]
  depends_on = [module.eks_mod]

}

resource "aws_security_group_rule" "eks_cluster_to_node_metrics_10251" {
  type                     = "ingress"
  from_port                = 10251
  to_port                  = 10251
  protocol                 = "tcp"
  security_group_id        = module.eks_mod.node_security_group_id
  source_security_group_id = module.eks_mod.cluster_primary_security_group_id
  description              = "Allow EKS control plane to reach metrics-server on 10251"
}

resource "aws_security_group_rule" "node_to_node_metrics_10250" {
  type                     = "ingress"
  from_port                = 10250
  to_port                  = 10250
  protocol                 = "tcp"
  security_group_id        = module.eks_mod.node_security_group_id
  source_security_group_id = module.eks_mod.node_security_group_id
  description              = "Allow node-to-node metrics scraping on 10250"

}


