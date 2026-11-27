output "alb_dns_name" {
  description = "DNS publico del balanceador"
  value       = aws_lb.main.dns_name
}

output "alb_arn_suffix" {
  description = "Sufijo del ARN del ALB (dimension LoadBalancer de CloudWatch)"
  value       = aws_lb.main.arn_suffix
}

output "target_group_arn_suffix" {
  description = "Sufijo del ARN del target group (dimension TargetGroup de CloudWatch)"
  value       = aws_lb_target_group.app.arn_suffix
}

output "ecr_repository_url" {
  description = "URL del repositorio ECR"
  value       = aws_ecr_repository.app.repository_url
}

output "ecr_repository_name" {
  description = "Nombre del repositorio ECR"
  value       = aws_ecr_repository.app.name
}

output "cluster_name" {
  description = "Nombre del cluster ECS"
  value       = aws_ecs_cluster.main.name
}

output "service_name" {
  description = "Nombre del servicio ECS"
  value       = aws_ecs_service.main.name
}

output "task_family" {
  description = "Familia de la definicion de tarea"
  value       = aws_ecs_task_definition.app.family
}

output "log_group_name" {
  description = "Grupo de logs de la aplicacion"
  value       = aws_cloudwatch_log_group.app.name
}
