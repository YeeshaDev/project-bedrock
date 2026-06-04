output "catalog_endpoint" {
  value = aws_db_instance.catalog.address
}

output "orders_endpoint" {
  value = aws_db_instance.orders.address
}

output "catalog_secret_arn" {
  value = aws_secretsmanager_secret.catalog_db.arn
}

output "orders_secret_arn" {
  value = aws_secretsmanager_secret.orders_db.arn
}
