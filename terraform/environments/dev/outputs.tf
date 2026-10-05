output "vpc_id" {
  value = module.networking.vpc_id
}

output "public_subnet_ids" {
  value = module.networking.public_subnet_ids
}

output "ecr_repository_url" {
  value = module.ecr.repository_url
}

output "alb_dns_name" {
  value = module.alb.alb_dns_name
}

output "ecs_cluster_name" {
  value = module.ecs.cluster_name
}

output "github_actions_role_arn" {
  value = module.github_oidc.role_arn
}

output "sns_alerts_topic_arn" {
  value = module.observability.sns_topic_arn
}
