variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "ecs-fargate-pipeline"
}

variable "azs" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b"]
}

variable "github_org" {
  type    = string
  default = "Lokesh9000"
}

variable "github_repo" {
  type    = string
  default = "ecs-fargate-pipeline"
}

variable "alert_email" {
  description = "leave blank to skip email alarm notifications"
  type        = string
  default     = ""
}

variable "image_tag" {
  description = "which image tag ECS should run - bumped manually until CI/CD does it"
  type        = string
  default     = "v4"
}

variable "autoscaling_target_cpu" {
  description = "target CPU% for the autoscaling policy - temporarily lowered during the load-test demo, see docs/incidents/03-load-autoscale.md"
  type        = number
  default     = 50
}
