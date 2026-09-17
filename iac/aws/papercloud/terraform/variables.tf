################################################################################
# Deployment inputs
################################################################################

variable "aws_region" {
  type    = string
  default = "ap-southeast-1"
}

variable "environment" {
  type    = string
  default = "prod"
}

variable "project_name" {
  type    = string
  default = "papercloud"
}

variable "domain_name" {
  description = "Public hostname used to access Paperless-ngx, e.g. paper.example.com."
  type        = string
}

variable "route53_zone_name" {
  description = "Existing Route 53 public zone name. If null, Terraform creates a zone for domain_name."
  type        = string
  default     = null
  nullable    = true
}

variable "route53_zone_id" {
  description = "Existing Route 53 public hosted zone ID. If null, Terraform creates a zone."
  type        = string
  default     = null
  nullable    = true
}

variable "vpc_cidr" {
  type    = string
  default = "10.42.0.0/16"
}

variable "ecs_cpu" {
  type    = number
  default = 2048
}

variable "ecs_memory" {
  type    = number
  default = 4096
}

variable "paperless_image" {
  type    = string
  default = "ghcr.io/paperless-ngx/paperless-ngx:3.1.3"
}

variable "paperless_timezone" {
  type    = string
  default = "Asia/Manila"
}

variable "database_instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "database_allocated_storage" {
  type    = number
  default = 20
}


# ========================================
#    Whitelisted IPs for ALB
# ========================================

variable "admin_allowed_cidrs" {
  description = "CIDR ranges allowed to access restricted application paths."
  type        = list(string)
}
