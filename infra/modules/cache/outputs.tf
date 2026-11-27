output "endpoint" {
  description = "Endpoint primario de Valkey"
  value       = aws_elasticache_replication_group.main.primary_endpoint_address
}

output "port" {
  description = "Puerto de Valkey"
  value       = aws_elasticache_replication_group.main.port
}

output "primary_cluster_id" {
  description = "Id del nodo primario (dimension CacheClusterId de CloudWatch)"
  value       = sort(tolist(aws_elasticache_replication_group.main.member_clusters))[0]
}
