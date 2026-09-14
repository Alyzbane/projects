variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short name used to prefix/tag every resource"
  type        = string
  default     = "leaderboard"
}

variable "instance_type" {
  description = "EC2 instance type for the dashboard host"
  type        = string
  default     = "t3.micro"
}

variable "ssh_allowed_cidr" {
  description = "CIDR allowed to SSH into the dashboard instance (used once by scripts/setup-www.sh to push the frontend). Restrict this to your own IP/32 in production."
  type        = string
  default     = "0.0.0.0/0"
}

variable "ami_id" {
  description = "Explicit AMI id for the dashboard instance. Leave null to auto-lookup the latest Ubuntu 24.04 AMI (real AWS). Set this when targeting LocalStack, where the real AMI catalog doesn't exist - see LOCALSTACK.md."
  type        = string
  default     = null
}
