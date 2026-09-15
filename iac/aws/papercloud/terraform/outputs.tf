output "paperless_url" {
  description = "Paperless-ngx URL."
  value       = local.paperless_url
}

output "alb_dns_name" {
  description = "Application Load Balancer DNS name."
  value       = aws_lb.paperless.dns_name
}

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint."
  value       = module.db.db_instance_endpoint
}

output "rds_master_secret_arn" {
  description = "RDS-managed master credential secret ARN."
  value       = module.db.db_instance_master_user_secret_arn
  sensitive   = true
}

output "paperless_secret_arn" {
  description = "Paperless secret key ARN."
  value       = aws_secretsmanager_secret.paperless_secret_key.arn
  sensitive   = true
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.paperless.name
}

output "ecs_service_name" {
  value = aws_ecs_service.paperless.name
}
