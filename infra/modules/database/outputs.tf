output "address" {
  description = "Endpoint DNS de RDS (sin puerto)"
  value       = aws_db_instance.main.address
}

output "port" {
  description = "Puerto de MySQL"
  value       = aws_db_instance.main.port
}

output "identifier" {
  description = "Identificador de la instancia (dimension de CloudWatch)"
  value       = aws_db_instance.main.identifier
}

output "db_name" {
  description = "Nombre de la base de datos"
  value       = aws_db_instance.main.db_name
}

output "username" {
  description = "Usuario administrador"
  value       = aws_db_instance.main.username
}

output "password" {
  description = "Contrasena generada (sensible)"
  value       = random_password.db.result
  sensitive   = true
}
