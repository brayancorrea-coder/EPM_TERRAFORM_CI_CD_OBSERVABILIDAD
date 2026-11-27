# Base de datos en memoria administrada: Amazon ElastiCache for Valkey (equivalente a
# Memorystore for Valkey del ejemplo). Es opcional (enable_cache) y solo la usa el
# dashboard de EPM para guardar 15 s los resultados agregados (cache.py).

resource "aws_security_group" "cache" {
  name        = "${var.project_name}-cache-sg"
  description = "Valkey: solo desde los contenedores EPM"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.project_name}-cache-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "cache_from_app" {
  security_group_id            = aws_security_group.cache.id
  description                  = "Valkey desde los contenedores EPM"
  referenced_security_group_id = var.app_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 6379
  to_port                      = 6379
}

resource "aws_elasticache_subnet_group" "main" {
  name       = "${var.project_name}-cache-subnets"
  subnet_ids = var.private_subnet_ids
}

resource "aws_elasticache_replication_group" "main" {
  replication_group_id = "${var.project_name}-valkey"
  description          = "Cache en memoria de EPM (Valkey)"

  engine               = "valkey"
  engine_version       = var.engine_version
  node_type            = var.node_type
  port                 = 6379
  parameter_group_name = var.parameter_group_name

  num_cache_clusters         = 1 + var.replica_count
  automatic_failover_enabled = var.replica_count > 0
  multi_az_enabled           = false

  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [aws_security_group.cache.id]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = false
  snapshot_retention_limit   = 0
  apply_immediately          = true

  tags = {
    Name = "${var.project_name}-valkey"
  }
}
