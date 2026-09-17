################################################################################
# Deployment outputs
################################################################################

output "paperless_url" {
  value = local.paperless_url
}

output "alb_dns_name" {
  value = module.alb.dns_name
}

output "route53_name_servers" {
  value = try(aws_route53_zone.this[0].name_servers, [])
}

output "rds_endpoint" {
  value = module.db.db_instance_endpoint
}

