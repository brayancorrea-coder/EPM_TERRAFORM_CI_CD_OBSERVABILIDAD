variable "project_name" {
  description = "Prefijo de los nombres de recursos"
  type        = string
}

variable "region" {
  description = "Region de AWS"
  type        = string
}

variable "alert_emails" {
  description = "Correos que reciben las alertas"
  type        = list(string)
}

variable "alb_arn_suffix" {
  description = "Sufijo del ARN del ALB (dimension LoadBalancer)"
  type        = string
}

variable "target_group_arn_suffix" {
  description = "Sufijo del ARN del target group (dimension TargetGroup)"
  type        = string
}

variable "cluster_name" {
  description = "Nombre del cluster ECS"
  type        = string
}

variable "service_name" {
  description = "Nombre del servicio ECS"
  type        = string
}

variable "log_group_name" {
  description = "Grupo de logs de la aplicacion"
  type        = string
}

variable "db_instance_id" {
  description = "Identificador de la instancia RDS"
  type        = string
}

variable "db_max_connections" {
  description = "max_connections configurado en RDS (base del umbral de conexiones)"
  type        = number
}

variable "enable_cache" {
  description = "Si existe el cache Valkey (agrega widgets y alarmas)"
  type        = bool
}

variable "cache_cluster_id" {
  description = "Id del nodo primario de Valkey (vacio si no hay cache)"
  type        = string
  default     = ""
}

variable "alb_latency_p95_seconds" {
  description = "Umbral de latencia p95 del backend (segundos)"
  type        = number
}

variable "alb_5xx_ratio_percent" {
  description = "Umbral del porcentaje de respuestas 5xx"
  type        = number
}

variable "ecs_cpu_percent" {
  description = "Umbral de CPU de ECS (%)"
  type        = number
}

variable "ecs_memory_percent" {
  description = "Umbral de memoria de ECS (%)"
  type        = number
}

variable "rds_cpu_percent" {
  description = "Umbral de CPU de RDS (%)"
  type        = number
}

variable "budget_limit_usd" {
  description = "Presupuesto mensual en USD (0 = no crear presupuesto)"
  type        = number
}
