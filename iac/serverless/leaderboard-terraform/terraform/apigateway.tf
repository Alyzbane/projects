resource "aws_api_gateway_rest_api" "leaderboard" {
  name        = "${var.project_name}-api"
  description = "REST API for the leaderboard service"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

# Path -> HTTP method -> backing Lambda
locals {
  endpoints = {
    scores = {
      http_method  = "POST"
      function_key = "score-submit"
    }
    leaderboard = {
      http_method  = "GET"
      function_key = "leaderboard-query"
    }
    player = {
      http_method  = "GET"
      function_key = "player-stats"
    }
    snapshot = {
      http_method  = "POST"
      function_key = "leaderboard-snapshot"
    }
    simulate = {
      http_method  = "POST"
      function_key = "score-simulator"
    }
  }
}

resource "aws_api_gateway_resource" "this" {
  for_each    = local.endpoints
  rest_api_id = aws_api_gateway_rest_api.leaderboard.id
  parent_id   = aws_api_gateway_rest_api.leaderboard.root_resource_id
  path_part   = each.key
}

# --- Real method (GET/POST) -> Lambda proxy integration ---

resource "aws_api_gateway_method" "main" {
  for_each      = local.endpoints
  rest_api_id   = aws_api_gateway_rest_api.leaderboard.id
  resource_id   = aws_api_gateway_resource.this[each.key].id
  http_method   = each.value.http_method
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "main" {
  for_each                = local.endpoints
  rest_api_id             = aws_api_gateway_rest_api.leaderboard.id
  resource_id             = aws_api_gateway_resource.this[each.key].id
  http_method             = aws_api_gateway_method.main[each.key].http_method
  integration_http_method = "POST" # Lambda proxy is always invoked via POST
  type                    = "AWS_PROXY"
  uri                     = module.lambda_function[each.value.function_key].lambda_function_invoke_arn
}

resource "aws_api_gateway_method" "options" {
  for_each      = local.endpoints
  rest_api_id   = aws_api_gateway_rest_api.leaderboard.id
  resource_id   = aws_api_gateway_resource.this[each.key].id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options" {
  for_each    = local.endpoints
  rest_api_id = aws_api_gateway_rest_api.leaderboard.id
  resource_id = aws_api_gateway_resource.this[each.key].id
  http_method = aws_api_gateway_method.options[each.key].http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "options" {
  for_each    = local.endpoints
  rest_api_id = aws_api_gateway_rest_api.leaderboard.id
  resource_id = aws_api_gateway_resource.this[each.key].id
  http_method = aws_api_gateway_method.options[each.key].http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "options" {
  for_each    = local.endpoints
  rest_api_id = aws_api_gateway_rest_api.leaderboard.id
  resource_id = aws_api_gateway_resource.this[each.key].id
  http_method = aws_api_gateway_method.options[each.key].http_method
  status_code = aws_api_gateway_method_response.options[each.key].status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type'"
    "method.response.header.Access-Control-Allow-Methods" = "'${each.value.http_method},OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

resource "aws_api_gateway_deployment" "this" {
  rest_api_id = aws_api_gateway_rest_api.leaderboard.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.this,
      aws_api_gateway_method.main,
      aws_api_gateway_integration.main,
      aws_api_gateway_method.options,
      aws_api_gateway_integration.options,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_integration.main,
    aws_api_gateway_integration.options,
  ]
}

resource "aws_api_gateway_stage" "prod" {
  rest_api_id   = aws_api_gateway_rest_api.leaderboard.id
  deployment_id = aws_api_gateway_deployment.this.id
  stage_name    = "prod"
}
