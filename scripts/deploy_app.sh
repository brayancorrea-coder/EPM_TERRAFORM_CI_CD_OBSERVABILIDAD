#!/usr/bin/env bash
# Despliega IMAGE_URI en ECS Fargate sin pasar por Terraform (la imagen es del pipeline de la app).
#  1) Registra una nueva revision de la tarea con la nueva imagen
#  2) Actualiza el servicio (si estaba en 0 contenedores lo sube a DESIRED_COUNT, por defecto 1)
#  3) Espera a que el servicio se estabilice (el circuit breaker de ECS hace rollback si no arranca)
#  4) Prueba de humo contra /health/ready del ALB; si falla, vuelve a la revision anterior
# Requiere: aws cli v2, jq, curl. Variables: IMAGE_URI (obligatoria), PROJECT_NAME, DESIRED_COUNT.
set -euo pipefail

PROJECT="${PROJECT_NAME:-epm-iac}"
IMAGE_URI="${IMAGE_URI:?Falta IMAGE_URI}"
DESIRED="${DESIRED_COUNT:-1}"
CLUSTER="${PROJECT}-cluster"
SERVICE="${PROJECT}-service"
FAMILY="${PROJECT}-app"
WORK="$(mktemp -d)"

echo ">> Estado actual del servicio ${SERVICE}"
PREV_TD="$(aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" --query 'services[0].taskDefinition' --output text)"
PREV_COUNT="$(aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" --query 'services[0].desiredCount' --output text)"
echo "   revision actual: ${PREV_TD} | contenedores: ${PREV_COUNT}"

echo ">> Nueva revision de la tarea con la imagen ${IMAGE_URI}"
# Se parte de la ultima revision de la familia (incluye cambios de variables hechos por Terraform)
aws ecs describe-task-definition --task-definition "$FAMILY" --query taskDefinition --output json > "$WORK/current.json"
jq --arg img "$IMAGE_URI" '
  {family, taskRoleArn, executionRoleArn, networkMode, containerDefinitions, volumes,
   placementConstraints, requiresCompatibilities, cpu, memory, runtimePlatform,
   pidMode, ipcMode, proxyConfiguration, ephemeralStorage}
  | with_entries(select(.value != null))
  | .containerDefinitions[0].image = $img' "$WORK/current.json" > "$WORK/new.json"
NEW_TD="$(aws ecs register-task-definition --cli-input-json "file://$WORK/new.json" --query 'taskDefinition.taskDefinitionArn' --output text)"
echo "   registrada: ${NEW_TD}"

COUNT="$PREV_COUNT"
if [ "$COUNT" -lt 1 ]; then COUNT="$DESIRED"; fi

echo ">> Actualizando el servicio (contenedores: ${COUNT})"
aws ecs update-service --cluster "$CLUSTER" --service "$SERVICE" --task-definition "$NEW_TD" --desired-count "$COUNT" > /dev/null
aws ecs wait services-stable --cluster "$CLUSTER" --services "$SERVICE"
echo "   servicio estable"

ALB_DNS="$(aws elbv2 describe-load-balancers --names "${PROJECT}-alb" --query 'LoadBalancers[0].DNSName' --output text)"
URL="http://${ALB_DNS}/health/ready"
echo ">> Prueba de humo: ${URL}"
OK=0
for i in $(seq 1 20); do
  CODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$URL" || true)"
  echo "   intento ${i}/20 -> HTTP ${CODE}"
  if [ "$CODE" = "200" ]; then OK=1; break; fi
  sleep 15
done

if [ "$OK" = "1" ]; then
  echo ">> Despliegue correcto: http://${ALB_DNS}"
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
      echo "## Despliegue de la aplicacion"
      echo "- Imagen: \`${IMAGE_URI}\`"
      echo "- Revision de la tarea: \`${NEW_TD}\`"
      echo "- URL: http://${ALB_DNS}"
    } >> "$GITHUB_STEP_SUMMARY"
  fi
  exit 0
fi

echo "!! La prueba de humo fallo."
if [ "$PREV_COUNT" -ge 1 ] && [ -n "$PREV_TD" ] && [ "$PREV_TD" != "None" ]; then
  echo "!! Rollback a ${PREV_TD}"
  aws ecs update-service --cluster "$CLUSTER" --service "$SERVICE" --task-definition "$PREV_TD" > /dev/null
  aws ecs wait services-stable --cluster "$CLUSTER" --services "$SERVICE" || true
fi
exit 1
