# ==============================================================================
# NETWORKING (ISOLATED VPC & PRIVATE SUBNETS)
# ==============================================================================

resource "aws_vpc" "this" {
  cidr_block           = "10.10.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = merge(local.tags, { Name = "${var.name_prefix}-vpc" })
}

resource "aws_subnet" "this" {
  for_each                = local.subnets
  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = false
  tags                    = merge(local.tags, { Name = "${var.name_prefix}-${each.key}" })
}

# Single private route table
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.tags, { Name = "${var.name_prefix}-private-rt" })
}

resource "aws_route_table_association" "private" {
  for_each       = local.subnets
  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.private.id
}

# ==============================================================================
# SECURITY GROUPS & PRIVATELINK ENDPOINTS
# ==============================================================================

resource "aws_security_group" "lambda" {
  name        = "${var.name_prefix}-lambda-sg"
  description = "Private boundary for Lambda compute"
  vpc_id      = aws_vpc.this.id

  # Restrict egress strictly to HTTPS traffic
  egress {
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTPS egress to VPC Endpoints"
  }

  tags = local.tags
}

resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.name_prefix}-vpce-sg"
  description = "Ingress for Lambda to reach VPC Interface Endpoints"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda.id]
    description     = "Allow inbound HTTPS from Lambda security group"
  }

  tags = local.tags
}

# DynamoDB Gateway Endpoint
resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.aws_region}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]
  tags              = local.tags
}

# SQS Interface Endpoint
resource "aws_vpc_endpoint" "sqs" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.aws_region}.sqs"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = [for s in aws_subnet.this : s.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  tags                = local.tags
}

# ==============================================================================
# WAF (Edge Security for CloudFront)
# ==============================================================================

resource "aws_wafv2_web_acl" "cloudfront" {
  provider = aws.us_east_1
  name     = "${var.name_prefix}-cf-waf"
  scope    = "CLOUDFRONT"

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedRules"
    priority = 0
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRules"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "IPRateLimit"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 500
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "IPRateLimit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name_prefix}-cf-waf"
    sampled_requests_enabled   = true
  }
}

# ==============================================================================
# CLOUDFRONT
# ==============================================================================

resource "aws_cloudfront_distribution" "api" {
  enabled         = true
  comment         = "${var.name_prefix} edge distribution for HTTP API"
  web_acl_id      = aws_wafv2_web_acl.cloudfront.arn
  is_ipv6_enabled = true

  origin {
    domain_name = replace(aws_apigatewayv2_api.http.api_endpoint, "https://", "")
    origin_id   = "http-api-origin"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "http-api-origin"
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = true
      headers      = ["Authorization", "Content-Type"]

      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 0
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = local.tags
}

# ==============================================================================
# DATASTORE & ASYNC MESSAGING
# ==============================================================================

resource "aws_dynamodb_table" "orders" {
  name         = "${var.name_prefix}-orders"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "order_id"

  attribute {
    name = "order_id"
    type = "S"
  }

  server_side_encryption {
    enabled = true
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = local.tags
}

resource "aws_sqs_queue" "orders_dlq" {
  name                      = "${var.name_prefix}-orders-dlq"
  message_retention_seconds = 1209600
  tags                      = local.tags
}

resource "aws_sqs_queue" "orders" {
  name                       = "${var.name_prefix}-orders"
  visibility_timeout_seconds = 180
  message_retention_seconds  = 345600
  delay_seconds              = 0
  tags                       = local.tags
}

resource "aws_sqs_queue_redrive_policy" "orders" {
  queue_url = aws_sqs_queue.orders.id
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.orders_dlq.arn
    maxReceiveCount     = 3
  })
}

# ==============================================================================
# IAM ROLES & POLICIES
# ==============================================================================

resource "aws_iam_role" "lambda" {
  for_each = local.lambda_roles
  name     = "${var.name_prefix}-${replace(each.key, "_", "-")}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  for_each   = local.lambda_roles
  role       = aws_iam_role.lambda[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "lambda_policy" {
  for_each = local.lambda_roles
  name     = "${var.name_prefix}-${replace(each.key, "_", "-")}-policy"
  role     = aws_iam_role.lambda[each.key].id

  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = concat(each.value, local.common_statements)
  })
}

# ==============================================================================
# COMPUTE (LAMBDA FUNCTIONS)
# ==============================================================================

data "archive_file" "producer" {
  type        = "zip"
  source_file = "${local.lambda_src_dir}/producer/handler.py"
  output_path = "${local.build_dir}/producer.zip"
}

data "archive_file" "worker" {
  type        = "zip"
  source_file = "${local.lambda_src_dir}/worker/handler.py"
  output_path = "${local.build_dir}/worker.zip"
}

data "archive_file" "dlq_reconciler" {
  type        = "zip"
  source_file = "${local.lambda_src_dir}/dlq_reconciler/handler.py"
  output_path = "${local.build_dir}/dlq_reconciler.zip"
}

resource "aws_lambda_function" "producer" {
  function_name    = "${var.name_prefix}-producer"
  role             = aws_iam_role.lambda["producer"].arn
  runtime          = "python3.12"
  handler          = "handler.handler"
  filename         = data.archive_file.producer.output_path
  source_code_hash = data.archive_file.producer.output_base64sha256
  timeout          = 10
  memory_size      = 256

  vpc_config {
    subnet_ids         = [for s in aws_subnet.this : s.id]
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.orders.name
      QUEUE_URL  = aws_sqs_queue.orders.url
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = local.tags
}

resource "aws_lambda_function" "worker" {
  function_name    = "${var.name_prefix}-worker"
  role             = aws_iam_role.lambda["worker"].arn
  runtime          = "python3.12"
  handler          = "handler.handler"
  filename         = data.archive_file.worker.output_path
  source_code_hash = data.archive_file.worker.output_base64sha256
  timeout          = 30
  memory_size      = 256

  vpc_config {
    subnet_ids         = [for s in aws_subnet.this : s.id]
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.orders.name
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = local.tags
}

resource "aws_lambda_function" "dlq_reconciler" {
  function_name    = "${var.name_prefix}-dlq-reconciler"
  role             = aws_iam_role.lambda["dlq_reconciler"].arn
  runtime          = "python3.12"
  handler          = "handler.handler"
  filename         = data.archive_file.dlq_reconciler.output_path
  source_code_hash = data.archive_file.dlq_reconciler.output_base64sha256
  timeout          = 30
  memory_size      = 128

  vpc_config {
    subnet_ids         = [for s in aws_subnet.this : s.id]
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.orders.name
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = local.tags
}

# Polling Event Source Mappings (With Partial Failure Reporting)
resource "aws_lambda_event_source_mapping" "worker" {
  event_source_arn                   = aws_sqs_queue.orders.arn
  function_name                      = aws_lambda_function.worker.arn
  batch_size                         = 5
  maximum_batching_window_in_seconds = 10
  function_response_types            = ["ReportBatchItemFailures"]

  scaling_config {
    maximum_concurrency = 5
  }
}

resource "aws_lambda_event_source_mapping" "dlq_reconciler" {
  event_source_arn = aws_sqs_queue.orders_dlq.arn
  function_name    = aws_lambda_function.dlq_reconciler.arn
  batch_size       = 5
}

# ==============================================================================
# COGNITO (OAuth2 M2M Client Credentials)
# ==============================================================================

resource "aws_cognito_user_pool" "clients" {
  name = "${var.name_prefix}-clients"
  tags = local.tags
}

resource "random_id" "cognito_domain_suffix" {
  byte_length = 4
}

resource "aws_cognito_user_pool_domain" "clients" {
  domain       = "${var.name_prefix}-${random_id.cognito_domain_suffix.hex}"
  user_pool_id = aws_cognito_user_pool.clients.id
}

resource "aws_cognito_resource_server" "orders_api" {
  identifier   = "orders-api"
  name         = "Orders API"
  user_pool_id = aws_cognito_user_pool.clients.id

  scope {
    scope_name        = "read"
    scope_description = "List and read orders"
  }

  scope {
    scope_name        = "write"
    scope_description = "Create and cancel orders"
  }
}

resource "aws_cognito_user_pool_client" "service_client" {
  name         = "${var.name_prefix}-service-client"
  user_pool_id = aws_cognito_user_pool.clients.id

  generate_secret                      = true
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["client_credentials"]
  allowed_oauth_scopes = [
    "${aws_cognito_resource_server.orders_api.identifier}/read",
    "${aws_cognito_resource_server.orders_api.identifier}/write",
  ]
  supported_identity_providers = ["COGNITO"]

  depends_on = [aws_cognito_resource_server.orders_api]
}

resource "aws_apigatewayv2_authorizer" "cognito_jwt" {
  api_id           = aws_apigatewayv2_api.http.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "${var.name_prefix}-cognito-jwt"

  jwt_configuration {
    audience = [aws_cognito_user_pool_client.service_client.id]
    issuer   = local.cognito_issuer
  }
}

# ==============================================================================
# API GATEWAY ROUTING
# ==============================================================================

resource "aws_apigatewayv2_api" "http" {
  name          = "${var.name_prefix}-api"
  protocol_type = "HTTP"
  tags          = local.tags

  cors_configuration {
    allow_origins = var.cors_allowed_origins
    allow_methods = ["GET", "POST", "DELETE", "OPTIONS"]
    allow_headers = ["Content-Type", "Authorization"]
    max_age       = 300
  }
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    detailed_metrics_enabled = true
    throttling_burst_limit   = 100
    throttling_rate_limit    = 50
  }

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_access_logs.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      responseLength = "$context.responseLength"
      integrationErr = "$context.integrationErrorMessage"
    })
  }

  tags = local.tags
}

resource "aws_apigatewayv2_integration" "producer" {
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.producer.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "create_order" {
  api_id               = aws_apigatewayv2_api.http.id
  route_key            = "POST /orders"
  target               = "integrations/${aws_apigatewayv2_integration.producer.id}"
  authorization_type   = "JWT"
  authorizer_id        = aws_apigatewayv2_authorizer.cognito_jwt.id
  authorization_scopes = ["${aws_cognito_resource_server.orders_api.identifier}/write"]
}

resource "aws_apigatewayv2_route" "list_orders" {
  api_id               = aws_apigatewayv2_api.http.id
  route_key            = "GET /orders"
  target               = "integrations/${aws_apigatewayv2_integration.producer.id}"
  authorization_type   = "JWT"
  authorizer_id        = aws_apigatewayv2_authorizer.cognito_jwt.id
  authorization_scopes = ["${aws_cognito_resource_server.orders_api.identifier}/read"]
}

resource "aws_apigatewayv2_route" "get_order" {
  api_id               = aws_apigatewayv2_api.http.id
  route_key            = "GET /orders/{order_id}"
  target               = "integrations/${aws_apigatewayv2_integration.producer.id}"
  authorization_type   = "JWT"
  authorizer_id        = aws_apigatewayv2_authorizer.cognito_jwt.id
  authorization_scopes = ["${aws_cognito_resource_server.orders_api.identifier}/read"]
}

resource "aws_apigatewayv2_route" "delete_order" {
  api_id               = aws_apigatewayv2_api.http.id
  route_key            = "DELETE /orders/{order_id}"
  target               = "integrations/${aws_apigatewayv2_integration.producer.id}"
  authorization_type   = "JWT"
  authorizer_id        = aws_apigatewayv2_authorizer.cognito_jwt.id
  authorization_scopes = ["${aws_cognito_resource_server.orders_api.identifier}/write"]
}

resource "aws_lambda_permission" "api" {
  statement_id  = "AllowApiGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.producer.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*"
}
