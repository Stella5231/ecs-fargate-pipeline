variable "project_name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "alb_security_group_id" {
  type = string
}

variable "target_group_arn" {
  type = string
}

variable "ecr_repository_url" {
  type = string
}

variable "container_port" {
  type    = number
  default = 8080
}

variable "image_tag" {
  description = "which image tag to run - the pipeline updates this"
  type        = string
  default     = "latest"
}

variable "cpu" {
  type    = number
  default = 256
}

variable "memory" {
  type    = number
  default = 512
}

variable "desired_count" {
  type    = number
  default = 1
}

variable "autoscaling_max_capacity" {
  type    = number
  default = 3
}

variable "autoscaling_target_cpu" {
  type    = number
  default = 50
}
