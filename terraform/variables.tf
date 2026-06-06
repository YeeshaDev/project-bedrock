variable "region" {
  description = "AWS region to deploy all resources"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "project-bedrock-cluster"
}

variable "vpc_name" {
  type    = string
  default = "project-bedrock-vpc"
}

variable "student_id" {
  type    = string
  default = "alt-soe-025-4808"
}

variable "db_password_catalog" {
  type      = string
  sensitive = true
}

variable "db_password_orders" {
  type      = string
  sensitive = true
}

variable "github_repo" {
  type        = string
  description = "GitHub repo in owner/name format"
  default     = "YeeshaDev/project-bedrock"
}
