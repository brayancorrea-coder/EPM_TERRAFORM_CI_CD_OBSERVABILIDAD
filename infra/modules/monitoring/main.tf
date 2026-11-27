# Observabilidad como codigo (equivale al modulo monitoring del ejemplo del profesor):
# canal de notificacion (SNS + correo), alarmas de CloudWatch, metrica basada en logs,
# dashboard y presupuesto. Todo se crea con terraform apply, sin clics en la consola.

locals {
  tg_dims      = tomap({ LoadBalancer = var.alb_arn_suffix, TargetGroup = var.target_group_arn_suffix })
  ecs_dims     = tomap({ ClusterName = var.cluster_name, ServiceName = var.service_name })
  rds_dims     = tomap({ DBInstanceIdentifier = var.db_instance_id })
  cache_dims   = tomap({ CacheClusterId = var.cache_cluster_id })
  alarm_target = [aws_sns_topic.alerts.arn]

  dashboard_url = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${var.project_name}-observabilidad"

  # Alarmas de una sola metrica. Se crean con for_each para no repetir bloques.
  base_alarms = {
    "backend-sin-contenedores-sanos" = {
      description         = "[CRITICA] El ALB no tiene ningun contenedor sano: el sitio esta caido. Revisar: ECS > servicio > Eventos, y los logs en CloudWatch (${var.log_group_name}). Si coincide con un despliegue, ECS hace rollback solo; si no, revisar RDS."
      namespace           = "AWS/ApplicationELB"
      metric_name         = "HealthyHostCount"
      dimensions          = local.tg_dims
      statistic           = "Minimum"
      extended_statistic  = null
      comparison_operator = "LessThanThreshold"
      threshold           = 1
      period              = 60
      evaluation_periods  = 2
      datapoints_to_alarm = 2
      treat_missing_data  = "breaching"
    }
    "backend-latencia-p95-alta" = {
      description         = "[ALTA] La latencia p95 del backend supera ${var.alb_latency_p95_seconds} s. Revisar CPU/memoria de ECS, conexiones y latencia de RDS."
      namespace           = "AWS/ApplicationELB"
      metric_name         = "TargetResponseTime"
      dimensions          = local.tg_dims
      statistic           = null
      extended_statistic  = "p95"
      comparison_operator = "GreaterThanThreshold"
      threshold           = var.alb_latency_p95_seconds
      period              = 60
      evaluation_periods  = 5
      datapoints_to_alarm = 3
      treat_missing_data  = "notBreaching"
    }
    "backend-cpu-alta" = {
      description         = "[MEDIA] CPU de los contenedores por encima de ${var.ecs_cpu_percent}%. Evaluar subir task_cpu o desired_count."
      namespace           = "AWS/ECS"
      metric_name         = "CPUUtilization"
      dimensions          = local.ecs_dims
      statistic           = "Average"
      extended_statistic  = null
      comparison_operator = "GreaterThanThreshold"
      threshold           = var.ecs_cpu_percent
      period              = 60
      evaluation_periods  = 5
      datapoints_to_alarm = 3
      treat_missing_data  = "notBreaching"
    }
    "backend-memoria-alta" = {
      description         = "[MEDIA] Memoria de los contenedores por encima de ${var.ecs_memory_percent}%. Evaluar subir task_memory."
      namespace           = "AWS/ECS"
      metric_name         = "MemoryUtilization"
      dimensions          = local.ecs_dims
      statistic           = "Average"
      extended_statistic  = null
      comparison_operator = "GreaterThanThreshold"
      threshold           = var.ecs_memory_percent
      period              = 60
      evaluation_periods  = 5
      datapoints_to_alarm = 3
      treat_missing_data  = "notBreaching"
    }
    "backend-tareas-en-ejecucion" = {
      description         = "[CRITICA] El servicio ECS no tiene tareas en ejecucion (Container Insights: RunningTaskCount < 1)."
      namespace           = "ECS/ContainerInsights"
      metric_name         = "RunningTaskCount"
      dimensions          = local.ecs_dims
      statistic           = "Minimum"
      extended_statistic  = null
      comparison_operator = "LessThanThreshold"
      threshold           = 1
      period              = 60
      evaluation_periods  = 3
      datapoints_to_alarm = 3
      treat_missing_data  = "breaching"
    }
    "db-cpu-alta" = {
      description         = "[MEDIA] CPU de RDS por encima de ${var.rds_cpu_percent}%. Revisar consultas lentas (logs slowquery) o subir la clase de instancia."
      namespace           = "AWS/RDS"
      metric_name         = "CPUUtilization"
      dimensions          = local.rds_dims
      statistic           = "Average"
      extended_statistic  = null
      comparison_operator = "GreaterThanThreshold"
      threshold           = var.rds_cpu_percent
      period              = 300
      evaluation_periods  = 3
      datapoints_to_alarm = 3
      treat_missing_data  = "notBreaching"
    }
    "db-poco-almacenamiento" = {
      description         = "[ALTA] Menos de 2 GiB libres en RDS. El almacenamiento crece solo hasta 40 GiB; revisar tablas de bitacora."
      namespace           = "AWS/RDS"
      metric_name         = "FreeStorageSpace"
      dimensions          = local.rds_dims
      statistic           = "Minimum"
      extended_statistic  = null
      comparison_operator = "LessThanThreshold"
      threshold           = 2 * 1024 * 1024 * 1024
      period              = 300
      evaluation_periods  = 1
      datapoints_to_alarm = 1
      treat_missing_data  = "notBreaching"
    }
    "db-poca-memoria" = {
      description         = "[MEDIA] Menos de 100 MiB de memoria libre en RDS."
      namespace           = "AWS/RDS"
      metric_name         = "FreeableMemory"
      dimensions          = local.rds_dims
      statistic           = "Minimum"
      extended_statistic  = null
      comparison_operator = "LessThanThreshold"
      threshold           = 100 * 1024 * 1024
      period              = 300
      evaluation_periods  = 3
      datapoints_to_alarm = 3
      treat_missing_data  = "notBreaching"
    }
    "db-conexiones-altas" = {
      description         = "[ALTA] Mas del 80% de max_connections (${var.db_max_connections}) en uso. Revisar el pool de conexiones de la app."
      namespace           = "AWS/RDS"
      metric_name         = "DatabaseConnections"
      dimensions          = local.rds_dims
      statistic           = "Maximum"
      extended_statistic  = null
      comparison_operator = "GreaterThanThreshold"
      threshold           = floor(var.db_max_connections * 0.8)
      period              = 60
      evaluation_periods  = 5
      datapoints_to_alarm = 3
      treat_missing_data  = "notBreaching"
    }
  }

  cache_alarms = {
    "cache-memoria-alta" = {
      description         = "[MEDIA] Uso de memoria de Valkey por encima de 80%."
      namespace           = "AWS/ElastiCache"
      metric_name         = "DatabaseMemoryUsagePercentage"
      dimensions          = local.cache_dims
      statistic           = "Maximum"
      extended_statistic  = null
      comparison_operator = "GreaterThanThreshold"
      threshold           = 80
      period              = 300
      evaluation_periods  = 3
      datapoints_to_alarm = 3
      treat_missing_data  = "notBreaching"
    }
    "cache-cpu-alta" = {
      description         = "[MEDIA] CPU del motor de Valkey por encima de 80%."
      namespace           = "AWS/ElastiCache"
      metric_name         = "EngineCPUUtilization"
      dimensions          = local.cache_dims
      statistic           = "Average"
      extended_statistic  = null
      comparison_operator = "GreaterThanThreshold"
      threshold           = 80
      period              = 300
      evaluation_periods  = 3
      datapoints_to_alarm = 3
      treat_missing_data  = "notBreaching"
    }
  }

  alarms = merge(local.base_alarms, var.enable_cache ? local.cache_alarms : {})
}

# ---------------------------------------------------------------------------
# Canal de notificacion: SNS + correo (equivale a notification_channel email)
# Cada destinatario recibe un correo de AWS y debe pulsar "Confirm subscription".
# ---------------------------------------------------------------------------
resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alertas"
}

resource "aws_sns_topic_subscription" "email" {
  for_each = toset(var.alert_emails)

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = each.value
}

# ---------------------------------------------------------------------------
# Alarmas de una metrica
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "simple" {
  for_each = local.alarms

  alarm_name          = "${var.project_name}-${each.key}"
  alarm_description   = each.value.description
  namespace           = each.value.namespace
  metric_name         = each.value.metric_name
  dimensions          = each.value.dimensions
  statistic           = each.value.statistic
  extended_statistic  = each.value.extended_statistic
  comparison_operator = each.value.comparison_operator
  threshold           = each.value.threshold
  period              = each.value.period
  evaluation_periods  = each.value.evaluation_periods
  datapoints_to_alarm = each.value.datapoints_to_alarm
  treat_missing_data  = each.value.treat_missing_data

  alarm_actions = local.alarm_target
  ok_actions    = local.alarm_target
}

# Alarma con matematica de metricas: porcentaje de respuestas 5xx del backend
resource "aws_cloudwatch_metric_alarm" "backend_5xx_ratio" {
  alarm_name          = "${var.project_name}-backend-ratio-5xx-alto"
  alarm_description   = "[CRITICA] Mas de ${var.alb_5xx_ratio_percent}% de las respuestas del backend son 5xx. Revisar los logs de la app (filtro ERROR) y la conectividad con MySQL (/health/ready)."
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.alb_5xx_ratio_percent
  evaluation_periods  = 5
  datapoints_to_alarm = 3
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "ratio"
    expression  = "IF(req > 0, 100 * FILL(err, 0) / req, 0)"
    label       = "% de respuestas 5xx"
    return_data = true
  }

  metric_query {
    id = "err"

    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "HTTPCode_Target_5XX_Count"
      dimensions  = local.tg_dims
      period      = 60
      stat        = "Sum"
    }
  }

  metric_query {
    id = "req"

    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "RequestCount"
      dimensions  = local.tg_dims
      period      = 60
      stat        = "Sum"
    }
  }

  alarm_actions = local.alarm_target
  ok_actions    = local.alarm_target
}

# ---------------------------------------------------------------------------
# Metrica basada en logs: errores de la aplicacion (equivale a google_logging_metric)
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_metric_filter" "app_errors" {
  name           = "${var.project_name}-errores-de-aplicacion"
  log_group_name = var.log_group_name
  pattern        = "?ERROR ?Traceback ?CRITICAL"

  metric_transformation {
    name          = "ErroresDeAplicacion"
    namespace     = "EPM/Aplicacion"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "app_errors" {
  alarm_name          = "${var.project_name}-backend-errores-en-logs"
  alarm_description   = "[ALTA] 5 o mas lineas ERROR/Traceback en 5 minutos en los logs de la aplicacion. Ver CloudWatch Logs > ${var.log_group_name}."
  namespace           = "EPM/Aplicacion"
  metric_name         = "ErroresDeAplicacion"
  statistic           = "Sum"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 5
  period              = 300
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  treat_missing_data  = "notBreaching"

  alarm_actions = local.alarm_target
  ok_actions    = local.alarm_target

  depends_on = [aws_cloudwatch_log_metric_filter.app_errors]
}

# ---------------------------------------------------------------------------
# Presupuesto mensual con aviso por correo (control de costos como codigo)
# ---------------------------------------------------------------------------
resource "aws_budgets_budget" "monthly" {
  count = var.budget_limit_usd > 0 ? 1 : 0

  name         = "${var.project_name}-presupuesto-mensual"
  budget_type  = "COST"
  limit_amount = tostring(var.budget_limit_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = var.alert_emails
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = var.alert_emails
  }
}
