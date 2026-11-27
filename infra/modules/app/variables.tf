variable "project_name" {
  description = "Prefijo de los nombres de recursos"
  type        = string
}

variable "region" {
  description = "Region de AWS (para el driver de logs)"
  type        = string
}

variable "vpc_id" {
  description = "ID de la VPC"
  type        = string
}

variable "public_subnet_ids" {
  description = "Subredes publicas para el ALB y los contenedores"
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "Security Group del balanceador"
  type        = string
}

variable "app_security_group_id" {
  description = "Security Group de los contenedores"
  type        = string
}

variable "app_port" {
  description = "Puerto de Gunicorn dentro del contenedor"
  type        = number
}

variable "health_check_path" {
  description = "Ruta que consulta el ALB y el contenedor para saber si la app esta viva"
  type        = string
  default     = "/health"
}

variable "app_image" {
  description = "Imagen inicial. Vacio = <repositorio ECR>:latest (despues la reemplaza el pipeline de la app)"
  type        = string
  default     = ""
}

variable "desired_count" {
  description = "Numero inicial de contenedores. 0 hasta que el pipeline de la app publique la primera imagen"
  type        = number
}

variable "task_cpu" {
  description = "CPU de la tarea Fargate (256 = 0,25 vCPU)"
  type        = number
}

variable "task_memory" {
  description = "Memoria de la tarea Fargate en MiB"
  type        = number
}

variable "log_retention_days" {
  description = "Dias de retencion de los logs en CloudWatch"
  type        = number
}

variable "db_host" {
  description = "Endpoint de MySQL"
  type        = string
}

variable "db_port" {
  description = "Puerto de MySQL"
  type        = number
}

variable "db_name" {
  description = "Nombre de la base de datos"
  type        = string
}

variable "db_username" {
  description = "Usuario de la base de datos"
  type        = string
}

variable "db_password" {
  description = "Contrasena de la base de datos (se guarda en Secrets Manager)"
  type        = string
  sensitive   = true
}

variable "cache_host" {
  description = "Endpoint de Valkey (vacio = cache deshabilitado)"
  type        = string
  default     = ""
}

variable "cache_port" {
  description = "Puerto de Valkey"
  type        = number
  default     = 6379
}
