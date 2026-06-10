locals {
  state_bucket_name = "${var.name_prefix}-db-lifecycle-state"
  lock_table_name   = "${var.name_prefix}-db-lifecycle-locks"

  logical_module_selector_base = {
    source = var.module_source
    baseInputs = {
      credential_secret_prefix = var.credential_secret_prefix
    }
  }

  logical_module_selector = var.module_version != "" ? merge(local.logical_module_selector_base, {
    version = var.module_version
  }) : local.logical_module_selector_base

  physical_module_selector = {
    source = var.physical_module_source
    baseInputs = {
      capacity_max   = var.physical_capacity_max
      security_class = var.physical_security_class
      subnet_ids     = var.subnet_ids
      vpc_id         = var.vpc_id
    }
  }

  lifecycle_profile = merge(
    {
      environments        = var.environments
      profiles            = var.profiles
      supportedEngines    = var.supported_engines
      supportedOperations = var.supported_operations
      backend = {
        provisioner   = "terraform"
        provider      = "aws-rds"
        stateBackend  = "s3"
        bucket        = local.state_bucket_name
        region        = var.region
        dynamodbTable = local.lock_table_name
        keyPrefix     = "lifecycle/"
        remoteState   = true
        locking       = true
      }
      credentialResolver = {
        runtime      = "aws_secrets_manager"
        secretPrefix = var.secrets_manager_allowed_prefix
      }
      moduleSelectors = {
        ensure_database                     = local.logical_module_selector
        ensure_physical_database_instance = local.physical_module_selector
        retire_database                   = local.logical_module_selector
      }
    },
    var.profile_id != "" ? { id = var.profile_id } : {},
  )

  lifecycle_profiles_json = jsonencode([local.lifecycle_profile])
}
