provider "aws" {
  region = "ap-northeast-2"
}

provider "kubernetes" {
  host                   = module.eks_mod.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks_mod.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks_mod.cluster_name, "--region", "ap-northeast-2"]
  }
}

provider "helm" {
  kubernetes = {
    host                   = module.eks_mod.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks_mod.cluster_certificate_authority_data)

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks_mod.cluster_name]
    }
  }
}
