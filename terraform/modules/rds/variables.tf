variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "eks_security_group_id" {
  type = string
}

variable "catalog_db_password" {
  type      = string
  sensitive = true
}

variable "orders_db_password" {
  type      = string
  sensitive = true
}
