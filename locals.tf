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

  superblocks_http_port = var.superblocks_agent_http_port
  superblocks_grpc_port = var.superblocks_agent_grpc_port

  tags = merge(var.tags, {
    superblocks_agent_tags = var.superblocks_agent_tags
  })

  region         = data.aws_region.current.name
  vpc_id         = var.create_vpc ? module.vpc[0].id : var.vpc_id
  lb_subnet_ids  = var.create_vpc ? module.vpc[0].lb_subnet_ids : var.lb_subnet_ids
  ecs_subnet_ids = var.create_vpc ? module.vpc[0].ecs_subnet_ids : var.ecs_subnet_ids

  lb_target_group_http_arns = var.create_lb ? concat([module.lb[0].target_group_http_arn], var.lb_target_group_http_arns) : var.lb_target_group_http_arns
  lb_target_group_grpc_arns = var.create_lb ? concat([module.lb[0].target_group_grpc_arn], var.lb_target_group_grpc_arns) : var.lb_target_group_grpc_arns


  certificate_arn = var.create_certs ? module.certs[0].certificate_arn : var.certificate_arn
  lb_ssl = var.create_certs ? true : var.certificate_arn != null
  agent_host_url  = "https://${var.subdomain}.${var.domain}"
}
