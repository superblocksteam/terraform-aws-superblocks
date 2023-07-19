locals {
  node_heap = var.container_memory * 0.75
}

#################################################################
# VPC
#################################################################
module "vpc" {
  count  = var.create_vpc ? 1 : 0
  source = "./modules/vpc"
}

#################################################################
# Security Group
#################################################################
module "sg" {
  count  = var.create_sg ? 1 : 0
  source = "./modules/security-group"
  vpc_id = local.vpc_id
}

#################################################################
# Load Balancer
#################################################################
module "lb" {
  count  = var.create_lb ? 1 : 0
  source = "./modules/load-balancer"

  internal           = var.lb_internal
  vpc_id             = local.vpc_id
  subnet_ids         = local.lb_subnet_ids
  security_group_ids = local.security_group_ids
  certificate_arn    = local.certificate_arn
}

#################################################################
# DNS & Certificate
#################################################################
module "dns" {
  count  = var.create_dns ? 1 : 0
  source = "./modules/dns"

  zone_name     = var.domain
  record_name   = var.subdomain
  alias_name    = local.lb_dns_name
  alias_zone_id = local.lb_zone_id
}

#################################################################
# ECS
#################################################################
module "ecs" {
  count  = var.deploy_in_ecs ? 1 : 0
  source = "./modules/ecs"

  region             = local.region
  subnet_ids         = local.ecs_subnet_ids
  security_group_ids = local.security_group_ids
  target_group_arn   = local.lb_target_group_arn

  task_role_arn = var.superblocks_agent_role_arn

  container_port         = var.superblocks_agent_port
  container_image        = var.superblocks_agent_image
  container_environment  = <<ENV
    [
      { "name": "__SUPERBLOCKS_AGENT_SERVER_URL", "value": "${var.superblocks_server_url}" },
      { "name": "__SUPERBLOCKS_WORKER_LOCAL_ENABLED", "value": "true" },
      { "name": "SUPERBLOCKS_WORKER_TLS_INSECURE", "value": "true" },
      { "name": "SUPERBLOCKS_AGENT_KEY", "value": "${var.superblocks_agent_key}" },
      { "name": "SUPERBLOCKS_CONTROLLER_DISCOVERY_ENABLED", "value": "false" },
      { "name": "SUPERBLOCKS_AGENT_HOST_URL", "value": "${local.agent_host_url}" },
      { "name": "SUPERBLOCKS_AGENT_ENVIRONMENT", "value": "${local.superblocks_agent_environment}" },
      { "name": "SUPERBLOCKS_AGENT_TAGS", "value": "${local.superblocks_agent_tags}" },
      { "name": "SUPERBLOCKS_AGENT_PORT", "value": "${var.superblocks_agent_port}" },
      { "name": "SUPERBLOCKS_AGENT_DATA_DOMAIN", "value": "${var.superblocks_agent_data_domain}" },
      { "name": "NODE_OPTIONS", "value": "--max_old_space_size=${local.node_heap}"}
    ]
  ENV
  container_cpu          = var.container_cpu
  container_memory       = var.container_memory
  container_min_capacity = var.container_min_capacity
  container_max_capacity = var.container_max_capacity
}
