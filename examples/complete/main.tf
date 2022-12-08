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
  container_port     = "8020"
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
  container_port   = "8020"

  container_environment = <<ENV
    [
      { "name": "__SUPERBLOCKS_AGENT_SERVER_URL", "value": "https://app.superblocks.com" },
      { "name": "__SUPERBLOCKS_WORKER_LOCAL_ENABLED", "value": "true" },
      { "name": "SUPERBLOCKS_WORKER_TLS_INSECURE", "value": "true" },
      { "name": "SUPERBLOCKS_WORKER_METRICS_PORT", "value": "9091" },
      { "name": "SUPERBLOCKS_AGENT_KEY", "value": "${var.superblocks_agent_key}" },
      { "name": "SUPERBLOCKS_CONTROLLER_DISCOVERY_ENABLED", "value": "false" },
      { "name": "SUPERBLOCKS_AGENT_HOST_URL", "value": "${local.agent_host_url}" },
      { "name": "SUPERBLOCKS_AGENT_ENVIRONMENT", "value": "*" },
      { "name": "SUPERBLOCKS_AGENT_PORT", "value": "8020" }
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
