locals {
  state_bucket_name = "${var.name_prefix}-db-lifecycle-state"
  lock_table_name   = "${var.name_prefix}-db-lifecycle-locks"

  module_selector_base = {
    source = var.module_source
    baseInputs = {
      isolation     = var.isolation
      region        = var.region
      secret_prefix = var.secret_prefix
      subnet_ids    = var.subnet_ids
      vpc_id        = var.vpc_id
    }
  }

  module_selector = var.module_version != "" ? merge(local.module_selector_base, {
    version = var.module_version
  }) : local.module_selector_base

  module_selectors = {
    for operation in var.supported_operations : operation => local.module_selector
  }

  lifecycle_profile = merge(
    {
      environments        = var.environments
      profiles            = var.profiles
      supportedEngines    = var.supported_engines
      supportedOperations = var.supported_operations
      backend = {
        provisioner    = "terraform"
        provider       = "aws-rds"
        stateBackend   = "s3"
        bucket         = local.state_bucket_name
        region         = var.region
        dynamodbTable  = local.lock_table_name
        keyPrefix      = "lifecycle/"
        remoteState    = true
        locking        = true
      }
      credentialResolver = {
        runtime       = "aws_secrets_manager"
        secretPrefix  = var.secret_prefix
      }
      moduleSelectors = local.module_selectors
    },
    var.profile_id != "" ? { id = var.profile_id } : {},
  )

  lifecycle_profiles_json = jsonencode([local.lifecycle_profile])
}
