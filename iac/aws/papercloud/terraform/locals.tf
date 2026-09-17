################################################################################
# Derived names and application settings
################################################################################

locals {
  name          = "${var.project_name}-${var.environment}"
  paperless_url = "https://${var.domain_name}"
  zone_name     = var.route53_zone_name != null ? var.route53_zone_name : var.domain_name
  zone_id       = var.route53_zone_id != null ? var.route53_zone_id : aws_route53_zone.this[0].zone_id
  # These paths require the ALB source-IP allowlist.
  admin_protected_paths = [
    "/admin/*",
    "/admin",
    "/api/users/*",
    "/api/groups/*",
  ]
}
