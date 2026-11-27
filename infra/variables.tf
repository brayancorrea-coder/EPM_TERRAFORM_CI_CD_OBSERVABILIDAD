# ---------------------------------------------------------------------------
# General
# ---------------------------------------------------------------------------
variable "aws_region" {
  description = "Region de AWS donde se despliega todo"
  type        = string
  default     = "us-east-2"
}

variable "project_name" {
  description = "Prefijo de los nombres de recursos (minusculas, numeros y guiones; maximo 20 caracteres)"
  type        = string
  default     = "epm-iac"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,19}$", var.project_name))
    error_message = "project_name debe empezar con una letra minuscula y tener entre 2 y 20 caracteres (a-z, 0-9, guion)."
  }
}

variable "environment" {
  description = "Nombre del entorno (etiqueta)"
  type        = string
  default     = "prod"
}

# ---------------------------------------------------------------------------
# Red
# ---------------------------------------------------------------------------
variable "vpc_cidr" {
  description = "CIDR de la VPC"
  type        = string
  default     = "10.20.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDRs de las 2 subredes publicas (ALB y contenedores)"
  type        = list(string)
  default     = ["10.20.1.0/24", "10.20.2.0/24"]

  validation {
    condition     = length(var.public_subnet_cidrs) == 2
    error_message = "Se requieren exactamente 2 subredes publicas (una por zona de disponibilidad)."
  }
}

variable "private_subnet_cidrs" {
  description = "CIDRs de las 2 subredes privadas (RDS y ElastiCache)"
  type        = list(string)
  default     = ["10.20.11.0/24", "10.20.12.0/24"]

  validation {
    condition     = length(var.private_subnet_cidrs) == 2
    error_message = "Se requieren exactamente 2 subredes privadas (una por zona de disponibilidad)."
  }
}

# ---------------------------------------------------------------------------
# Aplicacion (contenedor)
# ---------------------------------------------------------------------------
variable "app_port" {
  description = "Puerto de Gunicorn dentro del contenedor"
  type        = number
  default     = 8000
}

variable "app_image" {
  description = "Imagen inicial del contenedor. Vacio = <ECR>:latest. Luego la reemplaza el pipeline de la app"
  type        = string
  default     = ""
}

variable "app_desired_count" {
  description = "Contenedores iniciales. Se deja en 0 hasta que el pipeline de la app publique la primera imagen"
  type        = number
  default     = 0
}

variable "task_cpu" {
  description = "CPU de la tarea Fargate (256 = 0,25 vCPU)"
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "Memoria de la tarea Fargate (MiB)"
  type        = number
  default     = 512
}

variable "log_retention_days" {
  description = "Dias que se conservan los logs en CloudWatch"
  type        = number
  default     = 14
}

# ---------------------------------------------------------------------------
# Base de datos relacional (RDS MySQL)
# ---------------------------------------------------------------------------
variable "db_engine_version" {
  description = "Version de MySQL"
  type        = string
  default     = "8.0"
}

variable "db_instance_class" {
  description = "Clase de instancia de RDS"
  type        = string
  default     = "db.t4g.micro"
}

variable "db_name" {
  description = "Nombre de la base de datos (debe coincidir con MYSQL_DB de la app)"
  type        = string
  default     = "epm_db"
}

variable "db_username" {
  description = "Usuario administrador de MySQL (la contrasena la genera Terraform y vive en Secrets Manager)"
  type        = string
  default     = "epm_user"
}

variable "db_max_connections" {
  description = "Parametro max_connections de MySQL"
  type        = number
  default     = 100
}

variable "db_backup_retention_days" {
  description = "Dias de respaldos automaticos (el plan gratuito de AWS solo admite 1)"
  type        = number
  default     = 1
}

# ---------------------------------------------------------------------------
# Base de datos en memoria (ElastiCache for Valkey) - opcional
# ---------------------------------------------------------------------------
variable "enable_cache" {
  description = "Crear ElastiCache Valkey y conectar la app a el"
  type        = bool
  default     = false
}

variable "cache_engine_version" {
  description = "Version de Valkey"
  type        = string
  default     = "8.0"
}

variable "cache_parameter_group_name" {
  description = "Grupo de parametros por defecto de la version de Valkey"
  type        = string
  default     = "default.valkey8"
}

variable "cache_node_type" {
  description = "Tipo de nodo de ElastiCache"
  type        = string
  default     = "cache.t4g.micro"
}

variable "cache_replica_count" {
  description = "Replicas de lectura de Valkey (0 = un solo nodo)"
  type        = number
  default     = 0
}

# ---------------------------------------------------------------------------
# Observabilidad
# ---------------------------------------------------------------------------
variable "alert_emails" {
  description = "Correos que reciben las alarmas (cada uno debe confirmar la suscripcion de SNS)"
  type        = list(string)

  validation {
    condition = length(var.alert_emails) > 0 && alltrue([
      for e in var.alert_emails : can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", e)) && !strcontains(upper(e), "CAMBIAR")
    ])
    error_message = "alert_emails debe tener al menos un correo valido (cambie el valor CAMBIAR@... en env/prod.tfvars)."
  }
}

variable "alb_latency_p95_seconds" {
  description = "Umbral de latencia p95 del backend (segundos)"
  type        = number
  default     = 2
}

variable "alb_5xx_ratio_percent" {
  description = "Umbral del porcentaje de respuestas 5xx"
  type        = number
  default     = 5
}

variable "ecs_cpu_percent" {
  description = "Umbral de CPU de los contenedores (%)"
  type        = number
  default     = 80
}

variable "ecs_memory_percent" {
  description = "Umbral de memoria de los contenedores (%)"
  type        = number
  default     = 85
}

variable "rds_cpu_percent" {
  description = "Umbral de CPU de RDS (%)"
  type        = number
  default     = 80
}

variable "budget_limit_usd" {
  description = "Presupuesto mensual en USD con alertas por correo (0 = no crear)"
  type        = number
  default     = 10
}
