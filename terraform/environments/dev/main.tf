module "networking" {
  source = "../../modules/networking"

  project_name = var.project_name
  azs          = var.azs
}

module "ecr" {
  source = "../../modules/ecr"

  project_name = var.project_name
}

module "alb" {
  source = "../../modules/alb"

  project_name = var.project_name
  vpc_id       = module.networking.vpc_id
  subnet_ids   = module.networking.public_subnet_ids
}

module "ecs" {
  source = "../../modules/ecs"

  project_name           = var.project_name
  vpc_id                 = module.networking.vpc_id
  subnet_ids             = module.networking.public_subnet_ids
  alb_security_group_id  = module.alb.alb_security_group_id
  target_group_arn       = module.alb.target_group_arn
  ecr_repository_url     = module.ecr.repository_url
  image_tag              = var.image_tag
  autoscaling_target_cpu = var.autoscaling_target_cpu
}

module "github_oidc" {
  source = "../../modules/github_oidc"

  project_name           = var.project_name
  github_org             = var.github_org
  github_repo            = var.github_repo
  ecr_repository_arn     = module.ecr.repository_arn
  ecs_cluster_arn        = module.ecs.cluster_arn
  ecs_service_arn        = module.ecs.service_arn
  ecs_execution_role_arn = module.ecs.execution_role_arn
  ecs_task_role_arn      = module.ecs.task_role_arn
}

module "observability" {
  source = "../../modules/observability"

  project_name            = var.project_name
  alert_email             = var.alert_email
  alb_arn_suffix          = module.alb.alb_arn_suffix
  target_group_arn_suffix = module.alb.target_group_arn_suffix
  ecs_cluster_name        = module.ecs.cluster_name
  ecs_service_name        = module.ecs.service_name
}
