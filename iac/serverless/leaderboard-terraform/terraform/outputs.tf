output "api_invoke_url" {
  description = "API Gateway invoke URL (prod stage) - goes into env.js as API_BASE. NOTE: against LocalStack this still renders a real amazonaws.com hostname (it's computed client-side by the provider); use `rest_api_id` below to build the LocalStack URL instead - see LOCALSTACK.md."
  value       = aws_api_gateway_stage.prod.invoke_url
}

output "rest_api_id" {
  description = "API Gateway REST API id - combine with the LocalStack edge port to build the local invoke URL, e.g. http://localhost:4566/restapis/<id>/prod/_user_request_"
  value       = aws_api_gateway_rest_api.leaderboard.id
}

output "dashboard_public_ip" {
  description = "Public IP of the EC2 dashboard host"
  value       = aws_instance.dashboard.public_ip
}

output "dashboard_public_dns" {
  description = "Public DNS name of the EC2 dashboard host"
  value       = aws_instance.dashboard.public_dns
}

output "ssh_private_key_path" {
  description = "Path to the generated private key used to SSH into the dashboard host"
  value       = local_sensitive_file.private_key.filename
}

output "dashboard_ami_id" {
  description = "AMI ID used by the dashboard EC2 instance"
  value       = local.ami_id
}
