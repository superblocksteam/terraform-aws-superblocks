data "aws_region" "current" {
  lifecycle {
    # modules/app-db renders verify_database_infra_absence by default, and OPA
    # images before v1.53.0 exit at startup when it is present. Fail the plan
    # instead of shipping a task definition that cannot start. Only a semver
    # tag can be checked; digests, latest, and custom tags pass.
    precondition {
      condition     = !(local.lifecycle_config_verifies_infra_absence && local.agent_image_below_infra_absence_minimum)
      error_message = "superblocks_agent_image ${var.superblocks_agent_image} is older than v1.53.0, which App DB needs to run verify_database_infra_absence. Upgrade superblocks_agent_image to v1.53.0 or later, or set verify_infra_absence_enabled = false on the app-db module until you can."
    }
  }
}

locals {
  # if superblocks_agent_tags is not default, then
  #   use superblocks_agent_tags as is
  # else if superblocks_agent_tags is default, then
  #   if superblocks_agent_environment is *,
  #     use profile:* (default)
  #   else
  #     use profile:${superblocks_agent_environment}
  superblocks_agent_tags = var.superblocks_agent_tags != "profile:*" ? var.superblocks_agent_tags : var.superblocks_agent_environment == "*" ? "profile:*" : "profile:${var.superblocks_agent_environment}"

  lifecycle_config_verifies_infra_absence = anytrue([
    for env in var.superblocks_agent_environment_variables :
    env.name == "SUPERBLOCKS_DATABASE_LIFECYCLE_CONFIG" && length(regexall("\"verify_database_infra_absence\"", env.value)) > 0
  ])
  agent_image_semver = regexall(":v?([0-9]+)\\.([0-9]+)\\.([0-9]+)$", var.superblocks_agent_image)
  agent_image_below_infra_absence_minimum = try(
    tonumber(local.agent_image_semver[0][0]) < 1 || (tonumber(local.agent_image_semver[0][0]) == 1 && tonumber(local.agent_image_semver[0][1]) < 53),
    false
  )

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
