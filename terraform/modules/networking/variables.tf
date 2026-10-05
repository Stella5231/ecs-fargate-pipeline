variable "project_name" {
  description = "used as a prefix for resource names/tags"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "one CIDR per public subnet"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "azs" {
  description = "availability zones, one per subnet in public_subnet_cidrs"
  type        = list(string)
}
