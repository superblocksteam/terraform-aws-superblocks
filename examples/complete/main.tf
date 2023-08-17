provider "aws" {
  region = var.region
}

variable "region" {
  type    = string
  default = "us-east-1"
}

locals {
  name_prefix = "example-complete"
  tags        = {}
}

# Create your own VPC or use the sub-module in this package
module "vpc" {
  source = "../../modules/vpc"

  name_prefix     = local.name_prefix
  tags            = local.tags
  cidr_block      = "10.0.0.0/20"
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  private_subnets = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
}

locals {
  vpc_id         = module.vpc.id
  lb_subnet_ids  = module.vpc.lb_subnet_ids
  ecs_subnet_ids = module.vpc.ecs_subnet_ids
}

# Create your own security group or use the sub-module in this package
module "sg" {
  source = "../../modules/security-group"

  vpc_id              = local.vpc_id
  name_prefix         = local.name_prefix
  tags                = local.tags
  ingress_cidr_blocks = ["0.0.0.0/0"]
}

locals {
  security_group_ids = [module.sg.id]
}

# Create your own load balancer or use the sub-module in this package
module "lb" {
  source = "../../modules/load-balancer"

  internal           = false
  vpc_id             = local.vpc_id
  subnet_ids         = local.lb_subnet_ids
  security_group_ids = local.security_group_ids
  name_prefix        = local.name_prefix
  tags               = local.tags
  container_port     = "8080"
  listener_port      = "443"
  listener_protocol  = "HTTPS"
  certificate_arn    = local.certificate_arn
}

locals {
  lb_dns_name         = module.lb.dns_name
  lb_zone_id          = module.lb.zone_id
  lb_target_group_arn = module.lb.target_group_arn
}

# Create your own certificate or use the sub-module in this package
module "dns" {
  source = "../../modules/dns"

  zone_name     = "clarkthekoala.com"
  record_name   = "example-complete"
  alias_name    = local.lb_dns_name
  alias_zone_id = local.lb_zone_id
  name_prefix   = local.name_prefix
  tags          = local.tags
}

locals {
  certificate_arn = module.dns.certificate_arn
  agent_host_url  = "https://example-complete.clarkthekoala.com"
}

# Deploy Superblocks to AWS ECS
variable "superblocks_agent_key" {
  type      = string
  sensitive = true
  default   = "<SUPERBLOCKS_AGENT_KEY>"
}

module "ecs" {
  source = "../../modules/ecs"

  region             = "us-east-1"
  subnet_ids         = local.ecs_subnet_ids
  security_group_ids = local.security_group_ids
  target_group_arn   = local.lb_target_group_arn
  name_prefix        = local.name_prefix
  tags               = local.tags

  container_cpu    = "512"
  container_memory = "1024"
  container_image  = "ghcr.io/superblocksteam/agent"
  container_port   = "8080"

  container_environment  = <<ENV
    [
      { "name": "SUPERBLOCKS_ORCHESTRATOR_LOG_LEVEL", "value": "${var.superblocks_log_level}" },
      { "name": "SUPERBLOCKS_ORCHESTRATOR_HTTP_PORT", "value": "${local.superblocks_http_port}" },
      { "name": "SUPERBLOCKS_ORCHESTRATOR_GRPC_PORT", "value": "8081" },
      { "name": "SUPERBLOCKS_ORCHESTRATOR_METRICS_PORT", "value": "9090" },
      { "name": "SUPERBLOCKS_ORCHESTRATOR_GRPC_BIND", "value": "0.0.0.0" },
      { "name": "SUPERBLOCKS_ORCHESTRATOR_HTTP_BIND", "value": "0.0.0.0" },
      { "name": "SUPERBLOCKS_ORCHESTRATOR_GRPC_MSG_RES_MAX", "value": "${var.superblocks_grpc_msg_res_max}" },
      { "name": "SUPERBLOCKS_ORCHESTRATOR_GRPC_MSG_REQ_MAX", "value": "${var.superblocks_grpc_msg_req_max}" },
      { "name": "SUPERBLOCKS_ORCHESTRATOR_SUPERBLOCKS_URL", "value": "${var.superblocks_server_url}" },
      { "name": "SUPERBLOCKS_ORCHESTRATOR_SUPERBLOCKS_TIMEOUT", "value": "${var.superblocks_timeout}" },
      { "name": "SUPERBLOCKS_ORCHESTRATOR_OTEL_COLLECTOR_HTTP_URL", "value": "https://traces.intake.superblocks.com:443/v1/traces" },
      { "name": "SUPERBLOCKS_ORCHESTRATOR_EMITTER_REMOTE_INTAKE", "value": "https://logs.intake.superblocks.com" },
      { "name": "SUPERBLOCKS_ORCHESTRATOR_INTAKE_METADATA_URL", "value": "https://metadata.intake.superblocks.com" },
      { "name": "SUPERBLOCKS_ORCHESTRATOR_TRANSPORT_MODE", "value": "grpc" },
      { "name": "SUPERBLOCKS_ORCHESTRATOR_STORE_MODE", "value": "grpc" },
      { "name": "SUPERBLOCKS_AGENT_KEY", "value": "${var.superblocks_agent_key}" },
      { "name": "SUPERBLOCKS_ORCHESTRATOR_SUPERBLOCKS_KEY", "value": "${var.superblocks_agent_key}" },
      { "name": "SUPERBLOCKS_ORCHESTRATOR_FILE_SERVER_URL", "value": "http://127.0.0.1:${local.superblocks_http_port}/v2/files" },
      { "name": "SUPERBLOCKS_ORCHESTRATOR_AGENT_HOST_URL", "value": "${local.agent_host_url}" },
      { "name": "SUPERBLOCKS_ORCHESTRATOR_AGENT_ENVIRONMENT", "value": "${var.superblocks_agent_environment}" },
      { "name": "SUPERBLOCKS_ORCHESTRATOR_AGENT_TAGS", "value": "${local.superblocks_agent_tags}" },
      { "name": "SUPERBLOCKS_ORCHESTRATOR_DATA_DOMAIN", "value": "${var.superblocks_agent_data_domain}" }
    ]
  ENV

  container_min_capacity = "1"
  container_max_capacity = "5"

  container_scale_up_when_cpu_pct_above    = "50"
  container_scale_up_when_memory_pct_above = "50"
  ecs_cluster_capacity_providers           = ["FARGATE"]
}

output "agent_host_url" {
  value = local.agent_host_url
}
