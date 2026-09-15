variable "aws_region" {
  description = "AWS region for the deployment."
  type        = string
  default     = "ap-southeast-1"
}

variable "environment" {
  description = "Environment name."
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Short project name used for resource naming."
  type        = string
  default     = "papercloud"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.42.0.0/16"
}

variable "availability_zones" {
  description = "Two AZs for the VPC."
  type        = list(string)
  default     = ["ap-southeast-1a", "ap-southeast-1b"]
}

variable "ecs_cpu" {
  description = "Fargate task CPU units."
  type        = number
  default     = 1024
}

variable "ecs_memory" {
  description = "Fargate task memory in MiB."
  type        = number
  default     = 2048
}

variable "paperless_image" {
  description = "Pinned Paperless-ngx image. Update intentionally when upgrading."
  type        = string
  default     = "ghcr.io/paperless-ngx/paperless-ngx:3.1.3"
}

variable "paperless_timezone" {
  description = "Paperless timezone."
  type        = string
  default     = "Asia/Manila"
}

variable "database_instance_class" {
  description = "RDS PostgreSQL instance class."
  type        = string
  default     = "db.t4g.micro"
}

variable "database_allocated_storage" {
  description = "RDS storage in GiB."
  type        = number
  default     = 20
}

variable "base_url" {
  description = "Public base URL. Leave empty to use the ALB HTTP URL."
  type        = string
  default     = ""
}
