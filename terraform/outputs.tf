output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "region" {
  value = var.region
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "assets_bucket_name" {
  value = module.s3_lambda.bucket_name
}

output "dev_user_access_key_id" {
  value     = module.iam.dev_user_access_key_id
  sensitive = true
}

output "dev_user_secret_key" {
  value     = module.iam.dev_user_secret_key
  sensitive = true
}

output "dev_user_password" {
  value     = module.iam.dev_user_password
  sensitive = true
}

output "catalog_rds_endpoint" {
  value = module.rds.catalog_endpoint
}

output "orders_rds_endpoint" {
  value = module.rds.orders_endpoint
}

output "dynamodb_table_name" {
  value = module.dynamodb.table_name
}

output "github_actions_role_arn" {
  value = module.iam.github_actions_role_arn
}

output "lbc_role_arn" {
  value = module.eks.lbc_role_arn
}

output "cart_irsa_role_arn" {
  value = module.iam.cart_irsa_role_arn
}
