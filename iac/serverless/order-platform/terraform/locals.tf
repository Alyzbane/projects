# ==============================================================================
# SUBNET CONFIGURATION
# ==============================================================================

locals {
  subnets = {
    "private-a" = { cidr = "10.10.11.0/24", az = "${var.aws_region}a" }
    "private-b" = { cidr = "10.10.12.0/24", az = "${var.aws_region}b" }
  }

  tags = {
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

# ==============================================================================
# COGNITO / API GATEWAY JWT AUTHORIZER
# ==============================================================================

locals {
  cognito_issuer = var.use_localstack ? (
    "${var.localstack_url}/${aws_cognito_user_pool.clients.id}"
    ) : (
    "https://cognito-idp.${var.aws_region}.amazonaws.com/${aws_cognito_user_pool.clients.id}"
  )
}

# ==============================================================================
# Project Folder Structure
# ==============================================================================

locals {
  lambda_src_dir = "${path.module}/../src"
  build_dir      = "${path.module}/build"
}

# ==============================================================================
# LAMBDA IAM POLICY STATEMENTS
# ==============================================================================

locals {
  common_statements = [
    {
      Effect   = "Allow"
      Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "*"
    },
    {
      Effect   = "Allow"
      Action   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
      Resource = "*"
    }
  ]

  lambda_roles = {
    producer = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:DeleteItem", "dynamodb:Scan"]
        Resource = aws_dynamodb_table.orders.arn
      },
      {
        Effect   = "Allow"
        Action   = ["sqs:SendMessage"]
        Resource = aws_sqs_queue.orders.arn
      }
    ]

    worker = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:UpdateItem"]
        Resource = aws_dynamodb_table.orders.arn
      },
      {
        Effect   = "Allow"
        Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
        Resource = aws_sqs_queue.orders.arn
      }
    ]

    dlq_reconciler = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:UpdateItem"]
        Resource = aws_dynamodb_table.orders.arn
      },
      {
        Effect   = "Allow"
        Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
        Resource = aws_sqs_queue.orders_dlq.arn
      }
    ]
  }
}
