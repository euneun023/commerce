resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "9.4.11"
  namespace        = "argocd"
  create_namespace = true

  wait    = true
  timeout = 600

  depends_on = [
    helm_release.aws_load_balancer_controller
  ]

  values = [
    <<-YAML
    repoServer:
      resources:
        requests:
          cpu: 200m
          memory: 512Mi
        limits:
          cpu: 500m
          memory: 1Gi
      env:
        - name: ARGOCD_EXEC_TIMEOUT
          value: 3m
    YAML
  ]

  set = [
    {
      name  = "server.service.type"
      value = "ClusterIP"
    },
    {
      name  = "server.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-scheme"
      value = "internet-facing"
    }
  ]
}
