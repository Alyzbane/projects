terraform {
  required_version = ">=1.16.0"

  backend "local" {}

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = ">=3.3.0"
    }
  }
}
