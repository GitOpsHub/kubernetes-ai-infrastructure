output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value     = module.eks.cluster_endpoint
  sensitive = true
}

output "get_credentials_command" {
  value = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region}"
}
