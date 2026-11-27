# Dashboard de CloudWatch definido como codigo (equivale a google_monitoring_dashboard).
locals {
  cache_widgets = var.enable_cache ? [
    {
      type   = "metric"
      x      = 0
      y      = 24
      width  = 12
      height = 6
      properties = {
        title  = "Valkey: memoria y CPU (%)"
        view   = "timeSeries"
        region = var.region
        period = 300
        stat   = "Average"
        metrics = [
          ["AWS/ElastiCache", "DatabaseMemoryUsagePercentage", "CacheClusterId", var.cache_cluster_id],
          ["AWS/ElastiCache", "EngineCPUUtilization", "CacheClusterId", var.cache_cluster_id],
        ]
      }
    },
    {
      type   = "metric"
      x      = 12
      y      = 24
      width  = 12
      height = 6
      properties = {
        title  = "Valkey: aciertos y fallos del cache"
        view   = "timeSeries"
        region = var.region
        period = 300
        stat   = "Sum"
        metrics = [
          ["AWS/ElastiCache", "CacheHits", "CacheClusterId", var.cache_cluster_id],
          ["AWS/ElastiCache", "CacheMisses", "CacheClusterId", var.cache_cluster_id],
        ]
      }
    },
  ] : []

  dashboard_widgets = concat(
    [
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 2
        properties = {
          markdown = "# EPM - Observabilidad\nBackend (ALB + ECS Fargate), base de datos (RDS MySQL)${var.enable_cache ? " y cache (ElastiCache Valkey)" : ""}. Las alarmas notifican por correo via SNS. Dashboard gestionado con Terraform: no editar a mano."
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 2
        width  = 8
        height = 6
        properties = {
          title  = "ALB: solicitudes y errores 5xx"
          view   = "timeSeries"
          region = var.region
          period = 60
          stat   = "Sum"
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix, "TargetGroup", var.target_group_arn_suffix],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", var.alb_arn_suffix, "TargetGroup", var.target_group_arn_suffix],
            ["AWS/ApplicationELB", "HTTPCode_Target_4XX_Count", "LoadBalancer", var.alb_arn_suffix, "TargetGroup", var.target_group_arn_suffix],
          ]
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 2
        width  = 8
        height = 6
        properties = {
          title  = "ALB: latencia del backend (p50 / p95)"
          view   = "timeSeries"
          region = var.region
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_arn_suffix, "TargetGroup", var.target_group_arn_suffix, { stat = "p50", label = "p50" }],
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_arn_suffix, "TargetGroup", var.target_group_arn_suffix, { stat = "p95", label = "p95" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 2
        width  = 8
        height = 6
        properties = {
          title  = "Contenedores sanos / no sanos"
          view   = "timeSeries"
          region = var.region
          period = 60
          stat   = "Minimum"
          metrics = [
            ["AWS/ApplicationELB", "HealthyHostCount", "LoadBalancer", var.alb_arn_suffix, "TargetGroup", var.target_group_arn_suffix],
            ["AWS/ApplicationELB", "UnHealthyHostCount", "LoadBalancer", var.alb_arn_suffix, "TargetGroup", var.target_group_arn_suffix],
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 8
        width  = 8
        height = 6
        properties = {
          title  = "ECS: CPU y memoria (%)"
          view   = "timeSeries"
          region = var.region
          period = 60
          stat   = "Average"
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ClusterName", var.cluster_name, "ServiceName", var.service_name],
            ["AWS/ECS", "MemoryUtilization", "ClusterName", var.cluster_name, "ServiceName", var.service_name],
          ]
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 8
        width  = 8
        height = 6
        properties = {
          title  = "ECS: tareas en ejecucion"
          view   = "timeSeries"
          region = var.region
          period = 60
          stat   = "Average"
          metrics = [
            ["ECS/ContainerInsights", "RunningTaskCount", "ClusterName", var.cluster_name, "ServiceName", var.service_name],
            ["ECS/ContainerInsights", "DesiredTaskCount", "ClusterName", var.cluster_name, "ServiceName", var.service_name],
          ]
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 8
        width  = 8
        height = 6
        properties = {
          title  = "ECS: trafico de red (bytes)"
          view   = "timeSeries"
          region = var.region
          period = 60
          stat   = "Sum"
          metrics = [
            ["ECS/ContainerInsights", "NetworkRxBytes", "ClusterName", var.cluster_name, "ServiceName", var.service_name],
            ["ECS/ContainerInsights", "NetworkTxBytes", "ClusterName", var.cluster_name, "ServiceName", var.service_name],
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 14
        width  = 8
        height = 6
        properties = {
          title  = "RDS: CPU (%) y conexiones"
          view   = "timeSeries"
          region = var.region
          period = 60
          stat   = "Average"
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", var.db_instance_id],
            ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", var.db_instance_id, { yAxis = "right" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 14
        width  = 8
        height = 6
        properties = {
          title  = "RDS: memoria libre y almacenamiento libre (bytes)"
          view   = "timeSeries"
          region = var.region
          period = 300
          stat   = "Minimum"
          metrics = [
            ["AWS/RDS", "FreeableMemory", "DBInstanceIdentifier", var.db_instance_id],
            ["AWS/RDS", "FreeStorageSpace", "DBInstanceIdentifier", var.db_instance_id, { yAxis = "right" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 14
        width  = 8
        height = 6
        properties = {
          title  = "RDS: latencia de lectura y escritura (s)"
          view   = "timeSeries"
          region = var.region
          period = 60
          stat   = "Average"
          metrics = [
            ["AWS/RDS", "ReadLatency", "DBInstanceIdentifier", var.db_instance_id],
            ["AWS/RDS", "WriteLatency", "DBInstanceIdentifier", var.db_instance_id],
          ]
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 20
        width  = 16
        height = 4
        properties = {
          title  = "Logs de la aplicacion: ERROR / Traceback (ultimos)"
          view   = "table"
          region = var.region
          query  = "SOURCE '${var.log_group_name}' | fields @timestamp, @message | filter @message like /ERROR|Traceback|CRITICAL/ | sort @timestamp desc | limit 20"
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 20
        width  = 8
        height = 4
        properties = {
          title  = "Errores en logs (metrica propia)"
          view   = "timeSeries"
          region = var.region
          period = 300
          stat   = "Sum"
          metrics = [
            ["EPM/Aplicacion", "ErroresDeAplicacion"],
          ]
        }
      },
    ],
    local.cache_widgets
  )
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-observabilidad"
  dashboard_body = jsonencode({ widgets = local.dashboard_widgets })
}
