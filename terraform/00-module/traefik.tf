resource "helm_release" "traefik" {
  name             = "traefik"
  repository       = "https://traefik.github.io/charts"
  chart            = "traefik"
  version          = "37.0.0"
  namespace        = "traefik"
  create_namespace = true

  wait    = true
  timeout = 600

  values = [
    <<-YAML
    deployment:
      replicas: 1

    providers:
      kubernetesCRD:
        enabled: true
      kubernetesIngress:
        enabled: true

    service:
      type: LoadBalancer

    ports:
      web:
        port: 80
        expose:
          default: true
      websecure:
        port: 443
        expose:
          default: true
        tls:
          enabled: true

    ingressClass:
      enabled: true
      isDefaultClass: false
      name: traefik

    logs:
      general:
        level: INFO

    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: 300m
        memory: 256Mi
    YAML
  ]

  depends_on = [
    module.eks_mod,
    helm_release.aws_load_balancer_controller,
    helm_release.cert_manager
  ]
}
