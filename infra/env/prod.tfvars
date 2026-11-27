# Valores del entorno "prod" (equivale a env/prod.tfvars del ejemplo del profesor).
# NO hay contrasenas aqui: la de MySQL la genera Terraform y se guarda en Secrets Manager.
aws_region   = "us-east-2"
project_name = "epm-iac"
environment  = "prod"

# Correos que recibiran las alertas (SNS). CAMBIAR por correos reales del grupo.
alert_emails = ["brayancorrea1114112@correo.itm.edu.co"]

# Cache en memoria (ElastiCache Valkey). Pasar a true en un Pull Request para
# demostrar el flujo plan -> aprobacion -> apply de la infraestructura.
enable_cache = false

# Presupuesto mensual (USD) con aviso por correo; 0 desactiva el presupuesto.
budget_limit_usd = 10
