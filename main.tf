locals {
  node_heap = var.container_memory * 0.75
}

#################################################################
# VPC
#################################################################
module "vpc" {
  count       = var.create_vpc ? 1 : 0
  source      = "./modules/vpc"
  name_prefix = var.name_prefix
}

#################################################################
# Security Group
#################################################################
module "sg" {
  count       = var.create_sg ? 1 : 0
  source      = "./modules/security-group"
  name_prefix = var.name_prefix
  vpc_id      = local.vpc_id
  depends_on  = [module.vpc]
}

#################################################################
# Load Balancer
#################################################################
module "lb" {
  count  = var.create_lb ? 1 : 0
  source = "./modules/load-balancer"

  name_prefix        = var.name_prefix
  internal           = var.lb_internal
  vpc_id             = local.vpc_id
  subnet_ids         = local.lb_subnet_ids
  security_group_ids = local.security_group_ids
  certificate_arn    = local.certificate_arn
  zone_name          = var.domain
  record_name        = var.subdomain
  create_dns         = var.create_dns
  dns_ttl            = var.dns_ttl
  depends_on         = [module.vpc]
}

#################################################################
# DNS & Certificate
#################################################################
module "dns" {
  count  = var.create_dns ? 1 : 0
  source = "./modules/dns"

  name_prefix   = var.name_prefix
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

  name_prefix        = var.name_prefix
  region             = local.region
  subnet_ids         = local.ecs_subnet_ids
  security_group_ids = local.security_group_ids
  target_group_arn   = local.lb_target_group_arn

  task_role_arn = var.superblocks_agent_role_arn

  container_port  = local.superblocks_http_port
  container_image = var.superblocks_agent_image
  # SUPERBLOCKS_AGENT_ENVIRONMENT is being passed for backwards compatibility with older versions of the agent
  container_environment  = <<ENV
    [
      { "name": "SUPERBLOCKS_ORCHESTRATOR_LOG_LEVEL", "value": "${var.superblocks_log_level}" },
      { "name": "SUPERBLOCKS_ORCHESTRATOR_HTTP_PORT", "value": "${local.superblocks_http_port}" },
      { "name": "SUPERBLOCKS_ORCHESTRATOR_GRPC_MSG_RES_MAX", "value": "${var.superblocks_grpc_msg_res_max}" },
      { "name": "SUPERBLOCKS_ORCHESTRATOR_GRPC_MSG_REQ_MAX", "value": "${var.superblocks_grpc_msg_req_max}" },
      { "name": "SUPERBLOCKS_ORCHESTRATOR_SUPERBLOCKS_URL", "value": "${var.superblocks_server_url}" },
      { "name": "SUPERBLOCKS_ORCHESTRATOR_SUPERBLOCKS_TIMEOUT", "value": "${var.superblocks_timeout}" },
      { "name": "SUPERBLOCKS_ORCHESTRATOR_OTEL_COLLECTOR_HTTP_URL", "value": "https://traces.intake.superblocks.com:443/v1/traces" },
      { "name": "SUPERBLOCKS_ORCHESTRATOR_EMITTER_REMOTE_INTAKE", "value": "https://logs.intake.superblocks.com" },
      { "name": "SUPERBLOCKS_ORCHESTRATOR_INTAKE_METADATA_URL", "value": "https://metadata.intake.superblocks.com" },
      { "name": "SUPERBLOCKS_AGENT_KEY", "value": "${var.superblocks_agent_key}" },
      { "name": "SUPERBLOCKS_ORCHESTRATOR_SUPERBLOCKS_KEY", "value": "${var.superblocks_agent_key}" },
      { "name": "SUPERBLOCKS_ORCHESTRATOR_FILE_SERVER_URL", "value": "http://127.0.0.1:${local.superblocks_http_port}/v2/files" },
      { "name": "SUPERBLOCKS_ORCHESTRATOR_AGENT_HOST_URL", "value": "${local.agent_host_url}" },
      { "name": "SUPERBLOCKS_ORCHESTRATOR_AGENT_ENVIRONMENT", "value": "${var.superblocks_agent_environment}" },
      { "name": "SUPERBLOCKS_ORCHESTRATOR_AGENT_TAGS", "value": "${local.superblocks_agent_tags}" },
      { "name": "SUPERBLOCKS_ORCHESTRATOR_DATA_DOMAIN", "value": "${var.superblocks_agent_data_domain}" },
      { "name": "SUPERBLOCKS_ORCHESTRATOR_HANDLE_CORS", "value": "${var.superblocks_agent_handle_cors}" }
    ]
  ENV
  container_cpu          = var.container_cpu
  container_memory       = var.container_memory
  container_min_capacity = var.container_min_capacity
  container_max_capacity = var.container_max_capacity

  depends_on = [module.lb]
}
