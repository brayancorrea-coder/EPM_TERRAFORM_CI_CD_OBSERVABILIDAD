#!/usr/bin/env bash
# Preparacion UNICA de la cuenta AWS para los pipelines (se ejecuta una sola vez, a mano).
# Es el "huevo y la gallina" de la IaC: algo debe existir antes de que Terraform pueda correr solo.
# Crea: bucket S3 para el estado de Terraform, proveedor OIDC de GitHub y 3 roles de IAM
#   epm-gha-plan  (solo lectura)  -> PR: plan
#   epm-gha-apply (administrador) -> solo el entorno "prod" de GitHub: apply / destroy
#   epm-gha-app   (ECR + ECS)     -> rama main: despliegue de la aplicacion
# Se ejecuta en AWS CloudShell (ya autenticado, trae aws cli):
#   GITHUB_REPO=usuario/repositorio GITHUB_OWNER_ID=123 GITHUB_REPO_ID=456 bash scripts/bootstrap-aws.sh
#   GITHUB_REPO=usuario/repositorio bash scripts/bootstrap-aws.sh destroy   # deshacerlo todo
set -euo pipefail

GITHUB_REPO="${GITHUB_REPO:-brayancorrea-coder/EPM_TERRAFORM_CI_CD_OBSERVABILIDAD}"
AWS_REGION="${AWS_REGION:-us-east-2}"
PROJECT_NAME="${PROJECT_NAME:-epm-iac}"
ACTION="${1:-create}"

if [ "$ACTION" != "destroy" ]; then
  GITHUB_OWNER_ID="${GITHUB_OWNER_ID:?Defina GITHUB_OWNER_ID (ID numerico del propietario de GitHub)}"
  GITHUB_REPO_ID="${GITHUB_REPO_ID:?Defina GITHUB_REPO_ID (ID numerico del repositorio de GitHub)}"
  case "$GITHUB_REPO" in
    */*) ;;
    *) echo "GITHUB_REPO debe tener el formato propietario/repositorio" >&2; exit 1 ;;
  esac
  GITHUB_OWNER="${GITHUB_REPO%%/*}"
  GITHUB_REPO_NAME="${GITHUB_REPO#*/}"
  if [ -z "$GITHUB_OWNER" ] || [ -z "$GITHUB_REPO_NAME" ] || [[ "$GITHUB_REPO_NAME" == */* ]] ||
    ! [[ "$GITHUB_OWNER_ID" =~ ^[0-9]+$ ]] || ! [[ "$GITHUB_REPO_ID" =~ ^[0-9]+$ ]]; then
    echo "GITHUB_REPO, GITHUB_OWNER_ID o GITHUB_REPO_ID no son validos" >&2
    exit 1
  fi
  GITHUB_SUBJECT_PREFIX="repo:${GITHUB_OWNER}@${GITHUB_OWNER_ID}/${GITHUB_REPO_NAME}@${GITHUB_REPO_ID}"
fi

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
BUCKET="${STATE_BUCKET:-epm-tfstate-${ACCOUNT_ID}-${AWS_REGION}}"
OIDC_URL="token.actions.githubusercontent.com"
OIDC_ARN="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_URL}"
WORK="$(mktemp -d)"
export AWS_DEFAULT_REGION="$AWS_REGION"

ROLE_PLAN="epm-gha-plan"
ROLE_APPLY="epm-gha-apply"
ROLE_APP="epm-gha-app"

if [ "$ACTION" = "destroy" ]; then
  echo ">> Eliminando roles, proveedor OIDC y bucket de estado"
  for r in "$ROLE_PLAN" "$ROLE_APPLY" "$ROLE_APP"; do
    for p in $(aws iam list-attached-role-policies --role-name "$r" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || true); do
      aws iam detach-role-policy --role-name "$r" --policy-arn "$p"
    done
    for p in $(aws iam list-role-policies --role-name "$r" --query 'PolicyNames[]' --output text 2>/dev/null || true); do
      aws iam delete-role-policy --role-name "$r" --policy-name "$p"
    done
    aws iam delete-role --role-name "$r" 2>/dev/null || true
  done
  aws iam delete-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_ARN" 2>/dev/null || true
  echo "   (el bucket ${BUCKET} se vacia y borra con: aws s3 rb s3://${BUCKET} --force)"
  echo "   Antes de borrarlo, ejecute el workflow infra-destroy para no perder el estado."
  exit 0
fi

echo ">> Cuenta ${ACCOUNT_ID} | region ${AWS_REGION} | repositorio ${GITHUB_REPO}"
if [ "$ACTION" != "destroy" ]; then
  echo ">> Subject OIDC inmutable: ${GITHUB_SUBJECT_PREFIX}"
fi

# ---------------------------------------------------------------- 1. Bucket de estado
if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  echo ">> Bucket ${BUCKET} ya existe"
else
  echo ">> Creando bucket de estado ${BUCKET}"
  if [ "$AWS_REGION" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "$BUCKET" >/dev/null
  else
    aws s3api create-bucket --bucket "$BUCKET" --create-bucket-configuration "LocationConstraint=${AWS_REGION}" >/dev/null
  fi
fi
aws s3api put-bucket-versioning --bucket "$BUCKET" --versioning-configuration Status=Enabled
aws s3api put-public-access-block --bucket "$BUCKET" \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
aws s3api put-bucket-encryption --bucket "$BUCKET" \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

# ---------------------------------------------------------------- 2. Proveedor OIDC de GitHub
if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_ARN" >/dev/null 2>&1; then
  echo ">> Proveedor OIDC ya existe"
else
  echo ">> Creando proveedor OIDC de GitHub"
  aws iam create-open-id-connect-provider --url "https://${OIDC_URL}" \
    --client-id-list sts.amazonaws.com \
    --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1 >/dev/null
fi

# ---------------------------------------------------------------- 3. Roles
trust_policy() { # $1 = lista JSON de subjects permitidos
  cat <<JSON
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Federated": "${OIDC_ARN}"},
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {"${OIDC_URL}:aud": "sts.amazonaws.com"},
      "StringLike": {"${OIDC_URL}:sub": $1}
    }
  }]
}
JSON
}

ensure_role() { # $1 = nombre, $2 = archivo con la trust policy
  if aws iam get-role --role-name "$1" >/dev/null 2>&1; then
    aws iam update-assume-role-policy --role-name "$1" --policy-document "file://$2"
  else
    aws iam create-role --role-name "$1" --assume-role-policy-document "file://$2" >/dev/null
  fi
}

# plan: PRs y rama main (subject OIDC inmutable de GitHub)
trust_policy "[\"${GITHUB_SUBJECT_PREFIX}:pull_request\", \"${GITHUB_SUBJECT_PREFIX}:ref:refs/heads/main\"]" > "$WORK/trust-plan.json"
# apply/destroy: SOLO jobs que usan el entorno "prod" (con aprobacion)
trust_policy "[\"${GITHUB_SUBJECT_PREFIX}:environment:prod\"]" > "$WORK/trust-apply.json"
# app: solo la rama main
trust_policy "[\"${GITHUB_SUBJECT_PREFIX}:ref:refs/heads/main\"]" > "$WORK/trust-app.json"

echo ">> Creando roles de IAM"
ensure_role "$ROLE_PLAN" "$WORK/trust-plan.json"
ensure_role "$ROLE_APPLY" "$WORK/trust-apply.json"
ensure_role "$ROLE_APP" "$WORK/trust-app.json"

# --- permisos del rol plan: solo lectura + leer el estado + leer los secretos de EPM (para refrescar el estado)
aws iam attach-role-policy --role-name "$ROLE_PLAN" --policy-arn arn:aws:iam::aws:policy/ReadOnlyAccess
cat > "$WORK/policy-plan.json" <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {"Effect": "Allow", "Action": ["s3:ListBucket"], "Resource": "arn:aws:s3:::${BUCKET}"},
    {"Effect": "Allow", "Action": ["s3:GetObject"], "Resource": "arn:aws:s3:::${BUCKET}/*"},
    {"Effect": "Allow", "Action": ["secretsmanager:GetSecretValue"],
     "Resource": "arn:aws:secretsmanager:${AWS_REGION}:${ACCOUNT_ID}:secret:${PROJECT_NAME}/*"}
  ]
}
JSON
aws iam put-role-policy --role-name "$ROLE_PLAN" --policy-name estado-y-secretos --policy-document "file://$WORK/policy-plan.json"

# --- permisos del rol apply: administrador (simplificacion academica; en produccion se acota)
aws iam attach-role-policy --role-name "$ROLE_APPLY" --policy-arn arn:aws:iam::aws:policy/AdministratorAccess

# --- permisos del rol app: publicar en ECR y desplegar en ECS
cat > "$WORK/policy-app.json" <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {"Effect": "Allow", "Action": "ecr:GetAuthorizationToken", "Resource": "*"},
    {"Effect": "Allow",
     "Action": ["ecr:BatchCheckLayerAvailability", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart",
                "ecr:CompleteLayerUpload", "ecr:PutImage", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer",
                "ecr:DescribeRepositories", "ecr:DescribeImages", "ecr:DescribeImageScanFindings"],
     "Resource": "arn:aws:ecr:${AWS_REGION}:${ACCOUNT_ID}:repository/${PROJECT_NAME}-app"},
    {"Effect": "Allow",
     "Action": ["ecs:DescribeServices", "ecs:UpdateService", "ecs:DescribeTaskDefinition",
                "ecs:RegisterTaskDefinition", "ecs:DescribeTasks", "ecs:ListTasks", "ecs:DescribeClusters"],
     "Resource": "*"},
    {"Effect": "Allow", "Action": "elasticloadbalancing:DescribeLoadBalancers", "Resource": "*"},
    {"Effect": "Allow", "Action": "iam:PassRole",
     "Resource": ["arn:aws:iam::${ACCOUNT_ID}:role/${PROJECT_NAME}-ecs-execution",
                  "arn:aws:iam::${ACCOUNT_ID}:role/${PROJECT_NAME}-ecs-task"],
     "Condition": {"StringEquals": {"iam:PassedToService": "ecs-tasks.amazonaws.com"}}}
  ]
}
JSON
aws iam put-role-policy --role-name "$ROLE_APP" --policy-name ecr-y-ecs --policy-document "file://$WORK/policy-app.json"

cat <<EOF2

==================================================================
LISTO. En GitHub: Settings > Secrets and variables > Actions > pestana "Variables"
crear estas 5 variables de repositorio (no son secretos):

  AWS_REGION          = ${AWS_REGION}
  TF_STATE_BUCKET     = ${BUCKET}
  AWS_PLAN_ROLE_ARN   = arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_PLAN}
  AWS_APPLY_ROLE_ARN  = arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_APPLY}
  AWS_APP_ROLE_ARN    = arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_APP}

Y en Settings > Environments > New environment: "prod"
  (agregue su usuario en "Required reviewers" para exigir aprobacion manual).
==================================================================
EOF2
