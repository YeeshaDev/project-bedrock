resource "aws_db_subnet_group" "main" {
  name       = "project-bedrock-db-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = {
    Project = "karatu-2025-capstone"
  }
}

resource "aws_security_group" "rds" {
  name   = "project-bedrock-rds-sg"
  vpc_id = var.vpc_id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [var.eks_security_group_id]
  }

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.eks_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "project-bedrock-rds-sg"
    Project = "karatu-2025-capstone"
  }
}

resource "aws_db_instance" "catalog" {
  identifier             = "project-bedrock-catalog"
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  max_allocated_storage  = 50
  db_name                = "catalog"
  username               = "catalog_admin"
  password               = var.catalog_db_password
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  skip_final_snapshot    = true
  multi_az               = false
  publicly_accessible    = false
  storage_encrypted      = true

  tags = {
    Project = "karatu-2025-capstone"
  }
}

resource "aws_db_instance" "orders" {
  identifier             = "project-bedrock-orders"
  engine                 = "postgres"
  engine_version         = "16.3"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  max_allocated_storage  = 50
  db_name                = "orders"
  username               = "orders_admin"
  password               = var.orders_db_password
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  skip_final_snapshot    = true
  multi_az               = false
  publicly_accessible    = false
  storage_encrypted      = true

  tags = {
    Project = "karatu-2025-capstone"
  }
}

resource "aws_secretsmanager_secret" "catalog_db" {
  name                    = "project-bedrock/catalog-db-credentials"
  recovery_window_in_days = 0

  tags = {
    Project = "karatu-2025-capstone"
  }
}

resource "aws_secretsmanager_secret_version" "catalog_db" {
  secret_id = aws_secretsmanager_secret.catalog_db.id
  secret_string = jsonencode({
    host     = aws_db_instance.catalog.address
    port     = 3306
    dbname   = "catalog"
    username = "catalog_admin"
    password = var.catalog_db_password
  })
}

resource "aws_secretsmanager_secret" "orders_db" {
  name                    = "project-bedrock/orders-db-credentials"
  recovery_window_in_days = 0

  tags = {
    Project = "karatu-2025-capstone"
  }
}

resource "aws_secretsmanager_secret_version" "orders_db" {
  secret_id = aws_secretsmanager_secret.orders_db.id
  secret_string = jsonencode({
    host     = aws_db_instance.orders.address
    port     = 5432
    dbname   = "orders"
    username = "orders_admin"
    password = var.orders_db_password
  })
}
