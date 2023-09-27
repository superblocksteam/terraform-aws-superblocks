data "aws_region" "current" {}

locals {
  # if superblocks_agent_tags is not default, then
  #   use superblocks_agent_tags as is
  # else if superblocks_agent_tags is default, then
  #   if superblocks_agent_environment is *,
  #     use profile:* (default)
  #   else
  #     use profile:${superblocks_agent_environment}
  superblocks_agent_tags = var.superblocks_agent_tags != "profile:*" ? var.superblocks_agent_tags : var.superblocks_agent_environment == "*" ? "profile:*" : "profile:${var.superblocks_agent_environment}"

  superblocks_http_port = var.superblocks_agent_port

  tags = merge(var.tags, {
    superblocks_agent_tags = var.superblocks_agent_tags
  })

  region         = data.aws_region.current.name
  vpc_id         = var.create_vpc ? module.vpc[0].id : var.vpc_id
  lb_subnet_ids  = var.create_vpc ? module.vpc[0].lb_subnet_ids : var.lb_subnet_ids
  ecs_subnet_ids = var.create_vpc ? module.vpc[0].ecs_subnet_ids : var.ecs_subnet_ids

  lb_dns_name         = var.create_lb ? module.lb[0].dns_name : var.lb_dns_name
  lb_zone_id          = var.create_lb ? module.lb[0].zone_id : var.lb_zone_id
  lb_target_group_arn = var.create_lb ? module.lb[0].target_group_arn : var.lb_target_group_arn

  certificate_arn = var.create_certs ? module.certs[0].certificate_arn : var.certificate_arn
  agent_host_url  = "https://${var.subdomain}.${var.domain}"
}
