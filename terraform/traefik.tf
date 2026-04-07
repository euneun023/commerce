resource "helm_release" "traefik" {
  name  = "traefik"
  repository = "https://traefik.github.io/charts"
  chart = "traefik"
  namespace = "traefik"
  create_namespace = true
  version = "34.4.1"

  wait = true
  timeout = 600

  values = [
    yamlencode({
      service = {
        type = "LoadBalancer"
      }
      ports = {
        web = {
          port = 80
          expose = {
            default = true
          }
        }
        websecure = {
          port = 443
          expose = {
            default = true
          }
          tls = {
            enabled = true
          }
        }
      } 
      providers = {
        kubernetesCRD = {
          enabled = true
        }
        kubernetesIngress = {
          enabled = true
        }
      }
    })
  ]
}
