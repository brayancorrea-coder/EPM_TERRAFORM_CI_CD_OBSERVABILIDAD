# Infraestructura de EPM como codigo (Terraform + AWS)

Actividad 5 - IaC, CI/CD y Observabilidad. Adapta al proyecto EPM el ejemplo del profesor
(Terraform modular en GCP) a **AWS**, la nube donde EPM ya estaba desplegado manualmente (Actividad 4).

## Arquitectura

```
Internet --HTTP:80--> ALB (subredes publicas)
                        |  :8000
                        v
                  ECS Fargate (contenedor EPM: Flask + Gunicorn)  --3306-->  RDS MySQL 8.0 (subredes privadas)
                        |                                         --6379-->  ElastiCache Valkey (opcional)
                        +--> CloudWatch Logs  --> metrica propia + alarmas --> SNS --> correo
Secrets Manager (contrasena MySQL, SECRET_KEY)      ECR (imagenes)      S3 (estado de Terraform)
```

Diagrama completo: `docs/arquitectura.png`.

## Equivalencias con el ejemplo del profesor (GCP -> AWS)

| Ejemplo (GCP)                               | EPM (AWS)                                              | Modulo                    |
|---------------------------------------------|--------------------------------------------------------|---------------------------|
| VPC, subredes, Cloud NAT, firewall          | VPC, 2 subredes publicas + 2 privadas, Security Groups | `modules/networking`      |
| Cloud SQL MySQL (IP privada, PSA)           | RDS MySQL 8.0 (subredes privadas, SG)                   | `modules/database`        |
| Memorystore for Valkey (`enable_cache`)     | ElastiCache for Valkey (`enable_cache`)                 | `modules/cache`           |
| Cloud Run + HTTP Load Balancer              | ECS Fargate + Application Load Balancer + ECR           | `modules/app`             |
| Secret Manager                              | AWS Secrets Manager                                     | `modules/app`             |
| Cloud Monitoring (dashboard, alertas, canal)| CloudWatch (dashboard, alarmas, metrica de logs) + SNS  | `modules/monitoring`      |
| Estado remoto en GCS                        | Estado remoto en S3 con bloqueo nativo (`use_lockfile`) | `backend.tf`              |
| Cloud Build (plan / apply / destroy)        | GitHub Actions (plan / apply / destroy)                 | `.github/workflows/infra-*.yml` |
| Pipeline de la app (demo-wp)                | GitHub Actions `app-deploy.yml` (build, ECR, ECS)       | `.github/workflows/app-deploy.yml` |
| `env/prod.tfvars`, `.tflint.hcl`, trivy     | `env/prod.tfvars`, `.tflint.hcl`, checkov               | `infra/`                  |

## Estructura

```
infra/
  main.tf  variables.tf  outputs.tf  versions.tf  backend.tf
  env/prod.tfvars          <- valores del entorno (cambiar alert_emails)
  .tflint.hcl
  modules/
    networking/  database/  cache/  app/  monitoring/
```

## Decisiones de diseno

- **Sin NAT Gateway** (ahorra ~USD 33/mes): los contenedores estan en subredes publicas con IP publica
  solo para bajar la imagen de ECR; su Security Group unicamente admite trafico del ALB. RDS y Valkey estan en
  subredes privadas sin salida a Internet y solo aceptan trafico del Security Group de los contenedores.
- **Secretos fuera del codigo**: la contrasena de MySQL la genera Terraform (`random_password`), se guarda en
  Secrets Manager y ECS la inyecta como variable del contenedor. No aparece en `tfvars` ni en el repositorio.
- **Separacion infraestructura / aplicacion** (igual que el ejemplo): Terraform crea el servicio ECS y NO
  gestiona la imagen ni el numero de contenedores (`ignore_changes`). El pipeline de la app registra cada
  revision. Por eso el servicio nace con 0 contenedores y el primer despliegue de la app lo sube a 1.
- **Cache opcional**: `enable_cache = false/true`. El mismo contenedor funciona con o sin Valkey (`cache.py`).
- **Despliegue seguro**: circuit breaker de ECS (rollback automatico), prueba de humo en `/health/ready` y
  rollback manual a la revision previa si la prueba falla (`scripts/deploy_app.sh`).
- **Autenticacion sin llaves**: GitHub Actions asume roles de IAM por OIDC (`scripts/bootstrap-aws.sh`).
  El rol de `apply` solo puede ser asumido por el entorno `prod` (con aprobacion).

## Limites conocidos (trabajo futuro)

HTTP sin TLS (requiere dominio + ACM), una sola zona para RDS (sin Multi-AZ), sin WAF, sin logs de acceso del ALB,
sin autoescalado de ECS, cifrado en transito deshabilitado en Valkey, rol de apply con `AdministratorAccess`
(simplificacion academica). Ver `docs/evidencias/validacion/07-checkov.txt` para el detalle.

## Costo aproximado

Estimacion para `us-east-2` con `enable_cache=false` (confirmar en Billing / AWS Pricing Calculator):
ALB ~USD 0,023/h + 3 IPv4 publicas ~USD 0,015/h + Fargate 0,25 vCPU/0,5 GB ~USD 0,012/h + RDS db.t4g.micro
~USD 0,016/h  =>  **~USD 1,6 por dia**. Con Valkey: +~USD 0,016/h. **Destruir al terminar** (workflow `infra-destroy`).

## Uso local (opcional)

```bash
cd infra
terraform init -backend-config="bucket=<TF_STATE_BUCKET>"
terraform plan  -var-file=env/prod.tfvars
terraform apply -var-file=env/prod.tfvars
```
Requiere credenciales AWS y el bucket creado por `scripts/bootstrap-aws.sh`.
Despues del primer `init`, haga commit de `infra/.terraform.lock.hcl` para fijar las versiones de los proveedores.
