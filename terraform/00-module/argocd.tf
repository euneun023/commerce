resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true

  wait    = true
  timeout = 600

  depends_on = [
    helm_release.aws_load_balancer_controller
  ]
  set = [
    {
       name = "server.service.type"
       value = "LoadBalancer"
    }
  ]
}
