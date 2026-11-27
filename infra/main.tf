provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Course      = "ITM-Actividad5-IaC"
    }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

module "networking" {
  source = "./modules/networking"

  project_name         = var.project_name
  vpc_cidr             = var.vpc_cidr
  azs                  = local.azs
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  app_port             = var.app_port
}

module "database" {
  source = "./modules/database"

  project_name          = var.project_name
  vpc_id                = module.networking.vpc_id
  private_subnet_ids    = module.networking.private_subnet_ids
  app_security_group_id = module.networking.app_security_group_id
  engine_version        = var.db_engine_version
  instance_class        = var.db_instance_class
  db_name               = var.db_name
  db_username           = var.db_username
  max_connections       = var.db_max_connections
  backup_retention_days = var.db_backup_retention_days
}

# Cache en memoria opcional (enable_cache). Con count = 0 el modulo no crea nada.
module "cache" {
  source = "./modules/cache"
  count  = var.enable_cache ? 1 : 0

  project_name          = var.project_name
  vpc_id                = module.networking.vpc_id
  private_subnet_ids    = module.networking.private_subnet_ids
  app_security_group_id = module.networking.app_security_group_id
  engine_version        = var.cache_engine_version
  parameter_group_name  = var.cache_parameter_group_name
  node_type             = var.cache_node_type
  replica_count         = var.cache_replica_count
}

module "app" {
  source = "./modules/app"

  project_name          = var.project_name
  region                = var.aws_region
  vpc_id                = module.networking.vpc_id
  public_subnet_ids     = module.networking.public_subnet_ids
  alb_security_group_id = module.networking.alb_security_group_id
  app_security_group_id = module.networking.app_security_group_id
  app_port              = var.app_port
  app_image             = var.app_image
  desired_count         = var.app_desired_count
  task_cpu              = var.task_cpu
  task_memory           = var.task_memory
  log_retention_days    = var.log_retention_days

  db_host     = module.database.address
  db_port     = module.database.port
  db_name     = module.database.db_name
  db_username = module.database.username
  db_password = module.database.password

  cache_host = var.enable_cache ? module.cache[0].endpoint : ""
  cache_port = var.enable_cache ? module.cache[0].port : 6379
}

module "monitoring" {
  source = "./modules/monitoring"

  project_name            = var.project_name
  region                  = var.aws_region
  alert_emails            = var.alert_emails
  alb_arn_suffix          = module.app.alb_arn_suffix
  target_group_arn_suffix = module.app.target_group_arn_suffix
  cluster_name            = module.app.cluster_name
  service_name            = module.app.service_name
  log_group_name          = module.app.log_group_name
  db_instance_id          = module.database.identifier
  db_max_connections      = var.db_max_connections
  enable_cache            = var.enable_cache
  cache_cluster_id        = var.enable_cache ? module.cache[0].primary_cluster_id : ""
  alb_latency_p95_seconds = var.alb_latency_p95_seconds
  alb_5xx_ratio_percent   = var.alb_5xx_ratio_percent
  ecs_cpu_percent         = var.ecs_cpu_percent
  ecs_memory_percent      = var.ecs_memory_percent
  rds_cpu_percent         = var.rds_cpu_percent
  budget_limit_usd        = var.budget_limit_usd
}
