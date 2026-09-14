output "api_endpoint" {
  description = "CloudFront Distribution API Gateway URL"
  value       = "https://${aws_cloudfront_distribution.api.domain_name}"
}

output "api_gateway_invoke_url" {
  description = "Direct HTTP API invoke URL, bypassing CloudFront/WAF. Use this for local smoke testing — CloudFront is a global edge service and is not something to rely on being fully emulated locally."
  value       = aws_apigatewayv2_stage.default.invoke_url
}

output "api_gateway_id" {
  description = "HTTP API ID, used to build the LocalStack invoke hostname"
  value       = aws_apigatewayv2_api.http.id
}

output "cognito_token_endpoint" {
  description = "Cognito OAuth2 Token Endpoint (real AWS hosted UI domain — only resolves against actual AWS, never against LocalStack)"
  value       = "https://${aws_cognito_user_pool_domain.clients.domain}.auth.${var.aws_region}.amazoncognito.com/oauth2/token"
}

output "cognito_token_endpoint_localstack" {
  description = "Cognito OAuth2 Token Endpoint to use when running against LocalStack. The hosted-UI domain above is never emulated locally — this fixed internal path is the one that actually works."
  value       = "${var.localstack_url}/_aws/cognito-idp/oauth2/token"
}

output "cognito_user_pool_id" {
  description = "Cognito User Pool ID"
  value       = aws_cognito_user_pool.clients.id
}

output "cognito_client_id" {
  description = "Cognito Service Client ID"
  value       = aws_cognito_user_pool_client.service_client.id
}

output "cognito_client_secret" {
  description = "Cognito Service Client Secret"
  value       = aws_cognito_user_pool_client.service_client.client_secret
  sensitive   = true
}

output "cognito_scopes" {
  description = "Space-separated OAuth2 scopes configured on the service client, ready to drop into a token request"
  value       = join(" ", aws_cognito_user_pool_client.service_client.allowed_oauth_scopes)
}

output "cognito_issuer" {
  description = "Issuer configured on the API Gateway JWT authorizer (varies by use_localstack)"
  value       = local.cognito_issuer
}

output "queue_url" {
  description = "Orders SQS Queue URL"
  value       = aws_sqs_queue.orders.url
}

output "table_name" {
  description = "Orders DynamoDB Table Name"
  value       = aws_dynamodb_table.orders.name
}