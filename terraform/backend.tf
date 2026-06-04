terraform {
  backend "s3" {
    bucket = "project-bedrock-tfstate-alt-soe-025-4808"
    key    = "project-bedrock/terraform.tfstate"
    region = "us-east-1"
  }
}
