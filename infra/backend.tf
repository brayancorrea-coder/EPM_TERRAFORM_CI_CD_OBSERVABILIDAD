# Estado remoto en S3 con bloqueo nativo (equivalente al bucket GCS del ejemplo del profesor).
# El nombre del bucket NO se escribe aqui: se entrega en `terraform init` para que el
# repositorio no dependa de una cuenta concreta:
#   terraform init -backend-config="bucket=<TF_STATE_BUCKET>"
# (los workflows de GitHub Actions lo hacen con la variable de repositorio TF_STATE_BUCKET)
terraform {
  backend "s3" {
    key          = "epm/prod/terraform.tfstate"
    region       = "us-east-2"
    encrypt      = true
    use_lockfile = true
  }
}
