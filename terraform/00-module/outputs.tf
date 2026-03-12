output "private_subnet_ids" {
  value = module.vpc_mod.private_subnets
}

output "node_security_group_id" {
  value = module.eks_mod.node_security_group_id
}

output "cluster_primary_security_group_id" {
  value = module.eks_mod.cluster_primary_security_group_id
}
