output "app_url" {
  description = "URL publica de EPM (balanceador)"
  value       = "http://${module.app.alb_dns_name}"
}

output "health_url" {
  description = "URL del health check detallado (MySQL y cache)"
  value       = "http://${module.app.alb_dns_name}/health/ready"
}

output "ecr_repository_url" {
  description = "Repositorio ECR donde el pipeline publica las imagenes"
  value       = module.app.ecr_repository_url
}

output "ecr_repository_name" {
  description = "Nombre del repositorio ECR"
  value       = module.app.ecr_repository_name
}

output "ecs_cluster_name" {
  description = "Cluster ECS"
  value       = module.app.cluster_name
}

output "ecs_service_name" {
  description = "Servicio ECS"
  value       = module.app.service_name
}

output "ecs_task_family" {
  description = "Familia de la definicion de tarea"
  value       = module.app.task_family
}

output "log_group_name" {
  description = "Grupo de logs de la aplicacion"
  value       = module.app.log_group_name
}

output "db_endpoint" {
  description = "Endpoint de RDS MySQL (solo accesible desde la VPC)"
  value       = module.database.address
  sensitive   = true
}

output "cache_endpoint" {
  description = "Endpoint de Valkey (vacio si enable_cache = false)"
  value       = var.enable_cache ? module.cache[0].endpoint : ""
}

output "dashboard_url" {
  description = "Dashboard de CloudWatch"
  value       = module.monitoring.dashboard_url
}

output "sns_topic_arn" {
  description = "Topico SNS de alertas"
  value       = module.monitoring.sns_topic_arn
}

output "alarm_names" {
  description = "Alarmas de CloudWatch creadas"
  value       = module.monitoring.alarm_names
}
