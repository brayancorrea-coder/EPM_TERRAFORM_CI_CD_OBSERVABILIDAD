variable "project_name" {
  description = "Prefijo de los nombres de recursos"
  type        = string
}

variable "vpc_id" {
  description = "ID de la VPC"
  type        = string
}

variable "private_subnet_ids" {
  description = "Subredes privadas donde vive RDS"
  type        = list(string)
}

variable "app_security_group_id" {
  description = "Security Group de los contenedores (unico origen permitido hacia MySQL)"
  type        = string
}

variable "engine_version" {
  description = "Version de MySQL (se acepta la mayor, p. ej. 8.0)"
  type        = string
}

variable "instance_class" {
  description = "Clase de instancia RDS"
  type        = string
}

variable "db_name" {
  description = "Nombre de la base de datos que crea RDS"
  type        = string
}

variable "db_username" {
  description = "Usuario administrador de la base de datos"
  type        = string
}

variable "max_connections" {
  description = "Valor del parametro max_connections"
  type        = number
}

variable "backup_retention_days" {
  description = "Dias de retencion de respaldos automaticos (las cuentas del plan gratuito solo permiten 1)"
  type        = number
}
