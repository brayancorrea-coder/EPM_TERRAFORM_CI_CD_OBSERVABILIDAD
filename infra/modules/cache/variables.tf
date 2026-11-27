variable "project_name" {
  description = "Prefijo de los nombres de recursos"
  type        = string
}

variable "vpc_id" {
  description = "ID de la VPC"
  type        = string
}

variable "private_subnet_ids" {
  description = "Subredes privadas donde vive el cache"
  type        = list(string)
}

variable "app_security_group_id" {
  description = "Security Group de los contenedores (unico origen permitido hacia Valkey)"
  type        = string
}

variable "engine_version" {
  description = "Version de Valkey"
  type        = string
}

variable "parameter_group_name" {
  description = "Grupo de parametros por defecto que corresponde a la version de Valkey"
  type        = string
}

variable "node_type" {
  description = "Tipo de nodo de ElastiCache"
  type        = string
}

variable "replica_count" {
  description = "Numero de replicas de lectura (0 = un solo nodo)"
  type        = number
}
