# Guia de ejecucion - Actividad 5 (IaC + CI/CD + Observabilidad)

Tiempo estimado: 2 a 3 horas (el primer `apply` tarda ~15 min por RDS). Costo estimado: ~USD 1,6/dia
(ver `infra/README.md`); **destruya todo al terminar** (paso 10).

Cada paso termina con una **EVIDENCIA (E#)**: tome la captura indicada y peguela en el informe.

## 0. Requisitos
- Cuenta de GitHub (repositorio **publico** recomendado: los entornos con aprobacion manual en repos privados
  exigen plan de pago) y la cuenta de AWS usada en la Actividad 4 (region Ohio, us-east-2).
- Git instalado en su PC (o use "Add file > Upload files" de GitHub arrastrando las carpetas).

## 1. Subir el codigo a GitHub
1. En GitHub: **New repository** -> nombre `EPM-IaC` (publico) -> *sin* README.
2. En PowerShell, dentro de la carpeta descomprimida `EPM`:
```powershell
git init -b main
git add .
git commit -m "EPM: contenedor, Terraform, CI/CD y observabilidad"
git remote add origin https://github.com/<su-usuario>/EPM-IaC.git
# NO haga push todavia: primero configure AWS y las variables (pasos 2 a 4)
```
**E1**: captura del repositorio con las carpetas `infra/`, `.github/workflows/` y el `Dockerfile` (despues del push).

## 2. Ajustar el correo de alertas
Edite `infra/env/prod.tfvars` y cambie `CAMBIAR@correo.itm.edu.co` por su correo real (puede poner varios).
Si lo deja como esta, `terraform plan` falla a proposito con un mensaje claro. Guarde y haga
`git commit -am "correo de alertas"`.

## 3. Preparar AWS (una sola vez) con CloudShell
1. En la consola de AWS (region **us-east-2**) abra **CloudShell** (icono `>_` de la barra superior).
2. Suba `scripts/bootstrap-aws.sh` (menu *Actions > Upload file*) o pegue su contenido con `nano`, y ejecute:
```bash
GITHUB_REPO=<su-usuario>/EPM-IaC bash bootstrap-aws.sh
```
3. Al final imprime 5 valores. **E2**: captura de esa salida.

## 4. Configurar GitHub
1. *Settings > Secrets and variables > Actions > Variables > New repository variable*: cree las 5 variables
   que imprimio el paso 3 (`AWS_REGION`, `TF_STATE_BUCKET`, `AWS_PLAN_ROLE_ARN`, `AWS_APPLY_ROLE_ARN`, `AWS_APP_ROLE_ARN`).
2. *Settings > Environments > New environment* -> `prod` -> marque **Required reviewers** y agregue su usuario.
3. **E3**: captura de las variables y del entorno `prod` con el revisor.

## 5. Primer despliegue de la infraestructura (CD de la IaC - Opcion B)
```powershell
git push -u origin main
```
- *Actions > infra-apply*: el job **plan** corre solo y deja la vista previa del plan en el resumen de la ejecucion.
- El job **apply** queda en "Waiting": pulse **Review deployments -> prod -> Approve and deploy**.
- Dura ~15 min. Al terminar, el resumen muestra los `outputs` (URL del ALB, dashboard, etc.).

**E4**: captura del plan en el resumen (con el "Plan: N to add"). **E5**: captura del apply esperando aprobacion y
luego en verde con los outputs.

> Al terminar el apply, el workflow dispara solo `app-deploy` (siguiente paso). Si fallo antes por falta de
> variables, corrija y use *Actions > infra-apply > Run workflow*.

## 6. Despliegue de la aplicacion (CI/CD de la app - Opcion A)
`app-deploy` corre pruebas (pytest), construye la imagen, la sube a ECR, registra una revision en ECS, sube el
servicio a 1 contenedor y hace una prueba de humo en `/health/ready`.
- **E6**: *Actions > app-deploy* en verde (jobs `test` y `build-and-deploy`).
- **E7**: ECR -> repositorio `epm-iac-app` con la imagen (tag = sha del commit) y su escaneo de vulnerabilidades.
- **E8**: abra la URL `app_url` (ALB) -> pantalla de login de EPM -> ingrese `admin@epm.com` / `admin123` ->
  dashboard. Abra tambien `/health/ready` (JSON con `"mysql": "ok"`).

## 7. Recursos creados (evidencia de la IaC)
Capturas en la consola de AWS (region us-east-2): **E9** VPC y subredes; **E10** RDS (estado *Disponible*,
*Publicly accessible = No*); **E11** ECS cluster/servicio (1 tarea *Running*) y ALB (target *healthy*);
**E12** Secrets Manager (los 2 secretos, sin mostrar el valor) y S3 con el archivo de estado (con versionado).

## 8. Observabilidad
1. **Confirme la suscripcion**: AWS envia un correo "AWS Notification - Subscription Confirmation" -> *Confirm subscription*.
2. **E13**: CloudWatch -> Dashboards -> `epm-iac-observabilidad` (genere trafico navegando por la app unos minutos).
3. **E14**: CloudWatch -> Alarms: lista de alarmas (todas `OK` o `Insufficient data` al inicio).
4. **E15**: provoque una alarma y capture el correo recibido. Opcion rapida (CloudShell):
```bash
aws cloudwatch set-alarm-state --alarm-name epm-iac-backend-ratio-5xx-alto --state-value ALARM --state-reason "Prueba de notificacion" --region us-east-2
```
   Opcion real: `aws ecs update-service --cluster epm-iac-cluster --service epm-iac-service --desired-count 0 --region us-east-2`
   (a los ~3 min salta *sin-contenedores-sanos*); restaure con `--desired-count 1`.
5. **E16**: CloudWatch Logs -> grupo `/ecs/epm-iac` (lineas de Gunicorn) y *Logs Insights* con
   `fields @timestamp, @message | sort @timestamp desc | limit 20`.

## 9. Demostrar el flujo de IaC con un cambio (PR) y la base de datos en memoria
```powershell
git checkout -b feat/habilitar-cache
# edite infra/env/prod.tfvars:  enable_cache = true
git commit -am "Habilitar ElastiCache Valkey"
git push -u origin feat/habilitar-cache
```
1. En GitHub abra un **Pull Request** hacia `main`. Se ejecuta **infra-plan** (fmt, validate, tflint, checkov, plan) y
   comenta el plan en el PR (~6 recursos nuevos). **E17**: captura del PR con los checks y el comentario.
2. Haga *Merge*. Corre `infra-apply` -> apruebe `prod` -> crea Valkey (~10 min) -> dispara `app-deploy`.
3. **E18**: `/health/ready` ahora muestra `"cache": "ok"`; el dashboard muestra los widgets de Valkey y ElastiCache
   aparece en la consola. (La app guarda 15 s el resumen del dashboard en Valkey.)

## 10. Destruir todo (evita costos)
1. *Actions > infra-destroy > Run workflow* -> escriba `destroy` -> apruebe `prod`. **E19**: captura en verde.
2. En CloudShell: `aws s3 rb s3://<TF_STATE_BUCKET> --force` y
   `GITHUB_REPO=<usuario>/EPM-IaC bash bootstrap-aws.sh destroy` (borra roles y proveedor OIDC).
3. **E20**: consola de AWS sin RDS/ALB/ECS y *Billing* sin cargos nuevos. Recuerde que el plan gratuito
   se cierra al agotar los creditos o a los 6 meses.

## Problemas frecuentes
| Sintoma | Causa / solucion |
|---|---|
| `Not authorized to perform sts:AssumeRoleWithWebIdentity` | El nombre `GITHUB_REPO` no coincide exacto (mayusculas) o el job no usa `environment: prod`. Repita el bootstrap con el nombre correcto. |
| `alert_emails debe tener al menos un correo valido` | No cambio `CAMBIAR@...` en `infra/env/prod.tfvars` (paso 2). |
| El job `apply` no pide aprobacion | No creo el entorno `prod` con *Required reviewers* (paso 4) o el repo es privado en plan gratuito. |
| `FreeTierRestrictionError` / backup retention | Deje `db_backup_retention_days = 1` (valor por defecto). |
| ALB responde 503 | Aun no corrio `app-deploy` (el servicio nace con 0 contenedores) o la tarea no esta sana: ECS -> servicio -> *Events*. |
| `CannotPullContainerError` | La imagen no existe en ECR todavia; ejecute `app-deploy`. |
| Alarma `sin-contenedores-sanos` en ALARM al inicio | Normal hasta el primer `app-deploy`; vuelve a OK sola. |
| No llegan correos | Falta confirmar la suscripcion SNS (paso 8.1) o revise spam. |
| `ServiceLinkedRole`/`AccessDenied` al crear ECS, RDS o ALB | El rol `epm-gha-apply` debe tener `AdministratorAccess` (lo asigna el bootstrap). |
