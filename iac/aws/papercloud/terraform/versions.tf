terraform {
  required_version = ">= 1.11.1"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.64.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "3.7.2"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "papercloud"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
