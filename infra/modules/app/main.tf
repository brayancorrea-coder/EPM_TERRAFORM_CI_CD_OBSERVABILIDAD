# Servicio de aplicacion: ECR (imagenes) + ECS Fargate (contenedor) + ALB (balanceador)
# + Secrets Manager (credenciales) + CloudWatch Logs. Equivale al modulo cloudrun del ejemplo.

locals {
  image = var.app_image != "" ? var.app_image : "${aws_ecr_repository.app.repository_url}:latest"

  environment = concat(
    [
      { name = "MYSQL_HOST", value = var.db_host },
      { name = "MYSQL_PORT", value = tostring(var.db_port) },
      { name = "MYSQL_USER", value = var.db_username },
      { name = "MYSQL_DB", value = var.db_name },
    ],
    var.cache_host != "" ? [
      { name = "CACHE_HOST", value = var.cache_host },
      { name = "CACHE_PORT", value = tostring(var.cache_port) },
    ] : []
  )
}

# ---------------------------------------------------------------------------
# Registro de imagenes
# ---------------------------------------------------------------------------
resource "aws_ecr_repository" "app" {
  name                 = "${var.project_name}-app"
  image_tag_mutability = "MUTABLE"
  force_delete         = true # permite terraform destroy aunque tenga imagenes

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Conservar solo las 10 imagenes mas recientes"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# Secretos (la contrasena de MySQL y la clave de sesion de Flask no van como texto plano)
# ---------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "db_password" {
  name                    = "${var.project_name}/db-password"
  description             = "Contrasena de MySQL para EPM"
  recovery_window_in_days = 0 # borrado inmediato: permite destruir y volver a crear sin esperas
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = var.db_password
}

resource "random_password" "flask_secret_key" {
  length  = 48
  special = false
}

resource "aws_secretsmanager_secret" "flask_secret_key" {
  name                    = "${var.project_name}/flask-secret-key"
  description             = "SECRET_KEY de Flask para firmar las sesiones"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "flask_secret_key" {
  secret_id     = aws_secretsmanager_secret.flask_secret_key.id
  secret_string = random_password.flask_secret_key.result
}

# ---------------------------------------------------------------------------
# IAM: rol de ejecucion (baja imagen, escribe logs, lee secretos) y rol de tarea (sin permisos)
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "${var.project_name}-ecs-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "execution_secrets" {
  statement {
    sid       = "LeerSoloLosSecretosDeEPM"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.db_password.arn, aws_secretsmanager_secret.flask_secret_key.arn]
  }
}

resource "aws_iam_role_policy" "execution_secrets" {
  name   = "leer-secretos-epm"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution_secrets.json
}

# Rol que asume el codigo de la aplicacion: la app no llama a ningun servicio AWS, asi que no tiene permisos
resource "aws_iam_role" "task" {
  name               = "${var.project_name}-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

# ---------------------------------------------------------------------------
# Logs y cluster
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.project_name}"
  retention_in_days = var.log_retention_days
}

resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# ---------------------------------------------------------------------------
# Definicion de tarea y servicio (equivale a Cloud Run service del ejemplo)
# ---------------------------------------------------------------------------
resource "aws_ecs_task_definition" "app" {
  family                   = "${var.project_name}-app"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name      = "epm"
      image     = local.image
      essential = true

      portMappings = [
        {
          containerPort = var.app_port
          protocol      = "tcp"
        }
      ]

      environment = local.environment

      secrets = [
        { name = "MYSQL_PASSWORD", valueFrom = aws_secretsmanager_secret.db_password.arn },
        { name = "SECRET_KEY", valueFrom = aws_secretsmanager_secret.flask_secret_key.arn },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "epm"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "python -c \"import urllib.request; urllib.request.urlopen('http://127.0.0.1:${var.app_port}${var.health_check_path}', timeout=3)\" || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  ])
}

# ---------------------------------------------------------------------------
# Balanceador de carga (equivale al HTTP Load Balancer del ejemplo)
# ---------------------------------------------------------------------------
resource "aws_lb" "main" {
  name                       = "${var.project_name}-alb"
  load_balancer_type         = "application"
  internal                   = false
  security_groups            = [var.alb_security_group_id]
  subnets                    = var.public_subnet_ids
  drop_invalid_header_fields = true
  idle_timeout               = 60
}

resource "aws_lb_target_group" "app" {
  name                 = "${var.project_name}-tg"
  port                 = var.app_port
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = var.vpc_id
  deregistration_delay = 30

  health_check {
    path                = var.health_check_path
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

resource "aws_ecs_service" "main" {
  name            = "${var.project_name}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  health_check_grace_period_seconds  = 90
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  # Si un despliegue nuevo no se estabiliza, ECS vuelve solo a la version anterior
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = var.public_subnet_ids
    security_groups  = [var.app_security_group_id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "epm"
    container_port   = var.app_port
  }

  # La imagen (revision de la tarea) y el numero de contenedores los gestiona el pipeline de la
  # aplicacion (.github/workflows/app-deploy.yml); Terraform solo crea el servicio.
  # Es el mismo patron del ejemplo del profesor (ignore_changes sobre la imagen).
  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }

  depends_on = [aws_lb_listener.http]
}
