# Base de datos relacional administrada: Amazon RDS for MySQL 8.0 (equivalente a Cloud SQL del ejemplo).
# Vive en subredes privadas y solo acepta conexiones del Security Group de los contenedores.

resource "aws_security_group" "db" {
  name        = "${var.project_name}-db-sg"
  description = "MySQL: solo desde los contenedores EPM"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.project_name}-db-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "db_from_app" {
  security_group_id            = aws_security_group.db.id
  description                  = "MySQL desde los contenedores EPM"
  referenced_security_group_id = var.app_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
}

# La contrasena nunca se escribe en el repositorio ni en tfvars: la genera Terraform,
# queda en el estado (cifrado en S3) y el modulo app la publica en Secrets Manager.
resource "random_password" "db" {
  length  = 24
  special = false
}

resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnets"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name = "${var.project_name}-db-subnets"
  }
}

resource "aws_db_parameter_group" "main" {
  name_prefix = "${var.project_name}-mysql8-"
  family      = "mysql8.0"
  description = "Parametros de EPM: utf8mb4, conexiones y log de consultas lentas"

  parameter {
    name  = "character_set_server"
    value = "utf8mb4"
  }

  parameter {
    name  = "collation_server"
    value = "utf8mb4_unicode_ci"
  }

  parameter {
    name  = "max_connections"
    value = tostring(var.max_connections)
  }

  parameter {
    name  = "slow_query_log"
    value = "1"
  }

  parameter {
    name  = "long_query_time"
    value = "2"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Rol de Monitoreo Mejorado: RDS publica metricas del sistema operativo (CPU por proceso, memoria,
# disco) cada 60 s en CloudWatch Logs (grupo RDSOSMetrics).
data "aws_iam_policy_document" "rds_monitoring_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "rds_monitoring" {
  name               = "${var.project_name}-rds-monitoring"
  assume_role_policy = data.aws_iam_policy_document.rds_monitoring_assume.json
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

resource "aws_db_instance" "main" {
  identifier = "${var.project_name}-db"

  engine         = "mysql"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage     = 20
  max_allocated_storage = 40
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db.result

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  parameter_group_name   = aws_db_parameter_group.main.name
  publicly_accessible    = false
  multi_az               = false

  backup_retention_period    = var.backup_retention_days
  backup_window              = "08:00-09:00"
  maintenance_window         = "sun:09:30-sun:10:30"
  auto_minor_version_upgrade = true
  copy_tags_to_snapshot      = true

  # Logs del motor hacia CloudWatch Logs (observabilidad)
  enabled_cloudwatch_logs_exports = ["error", "slowquery"]
  monitoring_interval             = 60
  monitoring_role_arn             = aws_iam_role.rds_monitoring.arn

  # Entorno academico: se puede destruir con terraform destroy sin snapshot final
  deletion_protection = false
  skip_final_snapshot = true
  apply_immediately   = true

  tags = {
    Name = "${var.project_name}-db"
  }

  depends_on = [aws_iam_role_policy_attachment.rds_monitoring]
}
