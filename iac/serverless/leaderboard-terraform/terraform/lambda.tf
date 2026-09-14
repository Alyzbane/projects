# All 5 functions share the same runtime/handler/role shape
locals {
  lambda_functions = {
    score-submit = {
      description = "POST /scores - submit a player's score across all leaderboard periods"
    }
    leaderboard-query = {
      description = "GET /leaderboard - top-N players for a leaderboard period"
    }
    player-stats = {
      description = "GET /player - a player's rank & percentile across leaderboards"
    }
    leaderboard-snapshot = {
      description = "POST /snapshot - snapshot the top players of a leaderboard"
    }
    score-simulator = {
      description = "POST /simulate - generate randomized test data"
    }
  }
}

module "lambda_function" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "~> 7.0"

  for_each = local.lambda_functions

  function_name = "${var.project_name}-${each.key}"
  description   = each.value.description
  handler       = "handler.lambda_handler"
  runtime       = "python3.12"
  timeout       = 10
  memory_size   = 128

  source_path = "${path.module}/../lambda/${each.key}"

  publish = true

  create_role = false
  lambda_role = aws_iam_role.lambda_exec.arn

  allowed_triggers = {
    APIGateway = {
      service    = "apigateway"
      source_arn = "${aws_api_gateway_rest_api.leaderboard.execution_arn}/*/*"
    }
  }

  tags = local.tags
}
