variable "project_name" {
  description = "Prefijo de los nombres de recursos"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR de la VPC"
  type        = string
}

variable "azs" {
  description = "Zonas de disponibilidad a usar (una subred publica y una privada en cada una)"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDRs de las subredes publicas (ALB y contenedores), uno por zona"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDRs de las subredes privadas (RDS y ElastiCache), uno por zona"
  type        = list(string)
}

variable "app_port" {
  description = "Puerto en el que escucha Gunicorn dentro del contenedor"
  type        = number
}
