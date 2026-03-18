resource "aws_sqs_queue" "karpenter" {
  name = "${module.eks_mod.cluster_name}-karpenter-interruption"
}

resource "helm_release" "karpenter_crd" {
  name             = "karpenter-crd"
  namespace        = "kube-system"
  create_namespace = true

  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter-crd"
  version    = "1.8.1"

  wait    = true
  timeout = 600

  depends_on = [module.eks_mod]
}

resource "helm_release" "karpenter" {
  name             = "karpenter"
  namespace        = "kube-system"
  create_namespace = true

  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = "1.8.1"

  wait    = true
  timeout = 600

  set = [
    {
      name  = "settings.clusterName"
      value = module.eks_mod.cluster_name
    },
    {
      name  = "settings.clusterEndpoint"
      value = module.eks_mod.cluster_endpoint
    },
    {
      name  = "settings.interruptionQueue"
      value = aws_sqs_queue.karpenter.name
    },
    {
      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = aws_iam_role.karpenter_controller.arn
    }
  ]

  depends_on = [
    module.eks_mod,
    helm_release.karpenter_crd,
    aws_iam_role_policy.karpenter_controller,
    aws_sqs_queue.karpenter
  ]
}
