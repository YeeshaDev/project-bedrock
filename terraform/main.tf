module "vpc" {
  source       = "./modules/vpc"
  vpc_name     = var.vpc_name
  cluster_name = var.cluster_name
}

module "eks" {
  source             = "./modules/eks"
  cluster_name       = var.cluster_name
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  public_subnet_ids  = module.vpc.public_subnet_ids
  region             = var.region
}

module "iam" {
  source             = "./modules/iam"
  cluster_name       = var.cluster_name
  cluster_arn        = module.eks.cluster_arn
  oidc_provider_arn  = module.eks.oidc_provider_arn
  oidc_provider_url  = module.eks.oidc_provider_url
  oidc_issuer        = replace(module.eks.oidc_provider_url, "https://", "")
  assets_bucket_name = "bedrock-assets-${var.student_id}"
  dynamodb_table_arn = module.dynamodb.table_arn
  github_repo        = var.github_repo
}

module "rds" {
  source                = "./modules/rds"
  vpc_id                = module.vpc.vpc_id
  private_subnet_ids    = module.vpc.private_subnet_ids
  eks_security_group_id = module.eks.cluster_security_group_id
  catalog_db_password   = var.db_password_catalog
  orders_db_password    = var.db_password_orders
}

module "dynamodb" {
  source = "./modules/dynamodb"
}

module "s3_lambda" {
  source     = "./modules/s3-lambda"
  student_id = var.student_id
}

module "cloudwatch" {
  source            = "./modules/cloudwatch"
  cluster_name      = var.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
}

resource "aws_eks_access_entry" "dev_view" {
  cluster_name      = module.eks.cluster_name
  principal_arn     = module.iam.dev_user_arn
  kubernetes_groups = ["bedrock-dev-group"]

  depends_on = [module.eks, module.iam]
}
