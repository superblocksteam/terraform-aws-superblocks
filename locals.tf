data "aws_region" "current" {}

locals {
  env = var.superblocks_agent_environment == "*" ? "any" : var.superblocks_agent_environment
  tags = merge(var.tags, {
    superblocks_agent_environment = local.env
  })

  region         = data.aws_region.current.name
  vpc_id         = var.create_vpc ? module.vpc[0].id : var.vpc_id
  lb_subnet_ids  = var.create_vpc ? module.vpc[0].lb_subnet_ids : var.lb_subnet_ids
  ecs_subnet_ids = var.create_vpc ? module.vpc[0].ecs_subnet_ids : var.ecs_subnet_ids

  security_group_ids = var.create_sg ? [module.sg[0].id] : var.security_group_ids

  lb_dns_name         = var.create_lb ? module.lb[0].dns_name : var.lb_dns_name
  lb_zone_id          = var.create_lb ? module.lb[0].zone_id : var.lb_zone_id
  lb_target_group_arn = var.create_lb ? module.lb[0].target_group_arn : var.lb_target_group_arn

  certificate_arn = var.create_dns ? module.dns[0].certificate_arn : var.certificate_arn
  agent_host_url  = "https://${var.subdomain}.${var.domain}"
}
