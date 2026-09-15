locals {
  name = "${var.project_name}-${var.environment}"
}

locals {
  paperless_url = var.base_url != "" ? trimsuffix(var.base_url, "/") : "http://${aws_lb.paperless.dns_name}"
}
