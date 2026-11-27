output "dashboard_url" {
  description = "URL del dashboard de CloudWatch"
  value       = local.dashboard_url
}

output "sns_topic_arn" {
  description = "ARN del topico SNS de alertas"
  value       = aws_sns_topic.alerts.arn
}

output "alarm_names" {
  description = "Nombres de todas las alarmas creadas"
  value = concat(
    [for a in aws_cloudwatch_metric_alarm.simple : a.alarm_name],
    [aws_cloudwatch_metric_alarm.backend_5xx_ratio.alarm_name, aws_cloudwatch_metric_alarm.app_errors.alarm_name]
  )
}
