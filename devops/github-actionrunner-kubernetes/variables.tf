variable "github_url" {
  type        = string
  description = "Entity that the runners will belong to."
}

variable "github_token" {
  type        = string
  description = "GitHub personal access token (classic) with the repo and admin:org scopes for repository and organization runners."
  sensitive   = true
}