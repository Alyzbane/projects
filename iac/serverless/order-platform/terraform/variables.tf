variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "Target AWS region for infrastructure deployment"
}

variable "name_prefix" {
  type        = string
  default     = "platform"
  description = "Naming prefix applied to all managed resources"
}

variable "localstack_url" {
  type        = string
  default     = "http://localhost.localstack.cloud:4566"
  description = "Mock endpoint URL used for LocalStack testing"
}

variable "use_localstack" {
  type        = bool
  default     = false
  description = "True when this deployment targets LocalStack. Switches the Cognito JWT issuer URL used by the API Gateway authorizer from the real AWS format to the local one. Always false for real AWS deploys."
}

variable "cors_allowed_origins" {
  type        = list(string)
  default     = ["*"]
  description = "Origins allowed to call the HTTP API via CORS. Restrict this to your actual frontend domain(s) before going to production."
}
