module "database_lifecycle" {
  count  = var.database_lifecycle_enabled ? 1 : 0
  source = "./modules/database-lifecycle"

  name_prefix = var.name_prefix
  region      = local.region
  tags        = local.tags

  vpc_id     = local.vpc_id
  subnet_ids = local.ecs_subnet_ids

  environments                   = var.database_lifecycle.environments
  profiles                       = var.database_lifecycle.profiles
  credential_secret_prefix       = var.database_lifecycle.credential_secret_prefix
  secrets_manager_allowed_prefix = var.database_lifecycle.secrets_manager_allowed_prefix
  module_source                  = var.database_lifecycle.module_source
  physical_module_source         = var.database_lifecycle.physical_module_source
  module_version                 = var.database_lifecycle.module_version
  profile_id                     = var.database_lifecycle.profile_id
  physical_capacity_max          = var.database_lifecycle.physical_capacity_max
  physical_security_class        = var.database_lifecycle.physical_security_class
  task_role_arn                  = var.superblocks_agent_role_arn
}
