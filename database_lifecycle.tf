module "database_lifecycle" {
  count  = var.database_lifecycle_enabled ? 1 : 0
  source = "./modules/database-lifecycle"

  name_prefix = var.name_prefix
  region      = local.region
  tags        = local.tags

  vpc_id      = local.vpc_id
  subnet_ids  = local.ecs_subnet_ids
  environments = var.database_lifecycle.environments
  profiles    = var.database_lifecycle.profiles
  isolation   = var.database_lifecycle.isolation
  module_source  = var.database_lifecycle.module_source
  module_version = var.database_lifecycle.module_version
  secret_prefix  = var.database_lifecycle.secret_prefix
  profile_id     = var.database_lifecycle.profile_id
  task_role_arn    = var.superblocks_agent_role_arn
}
