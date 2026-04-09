resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = "1.20.1"
  namespace        = "cert-manager"
  create_namespace = true

  wait    = true
  timeout = 600

  values = [
    <<-YAML
    crds:
      enabled: true

    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: 300m
        memory: 256Mi

    webhook:
      resources:
        requests:
          cpu: 50m
          memory: 64Mi
        limits:
          cpu: 150m
          memory: 128Mi

    cainjector:
      resources:
        requests:
          cpu: 50m
          memory: 64Mi
        limits:
          cpu: 150m
          memory: 128Mi
    YAML
  ]

  depends_on = [
    module.eks_mod,
    helm_release.aws_load_balancer_controller
  ]
}
