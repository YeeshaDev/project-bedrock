variable "cluster_name" {
  type = string
}

variable "cluster_arn" {
  type = string
}

variable "oidc_provider_arn" {
  type = string
}

variable "oidc_provider_url" {
  type = string
}

variable "assets_bucket_name" {
  type = string
}

variable "dynamodb_table_arn" {
  type = string
}

variable "oidc_issuer" {
  type        = string
  description = "OIDC issuer URL without https://"
}

variable "github_repo" {
  type        = string
  description = "GitHub repo in owner/name format, e.g. myusername/project-bedrock"
}
