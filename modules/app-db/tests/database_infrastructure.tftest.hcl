# App Databases beta exposes one database infrastructure control. The app-db
# module must normalize that control for the shared physical module while
# keeping low-level capacity and engine selection out of the customer surface.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }
}

variables {
  agent_name         = "opa1"
  agent_tags         = ["nonprod", "production"]
  connector_role_arn = "arn:aws:iam::123456789012:role/sb-app-db-opa1-connector"
  key_prefix         = "app-db/opa1"
  region             = "us-east-1"
  state_bucket_name  = "sb-app-db-us-east-1-123456789012"

  physical_module_inputs = {
    monitoring_role_arn = "arn:aws:iam::123456789012:role/sb-app-db-enhanced-monitoring"
    subnet_ids          = ["subnet-0000000000000001", "subnet-0000000000000002"]
    vpc_id              = "vpc-0123456789abcdef0"
  }
}

run "scale_to_zero_defaults_false" {
  command = plan

  assert {
    condition = jsondecode([
      for env in output.ecs_env_vars : env.value
      if env.name == "SUPERBLOCKS_DATABASE_LIFECYCLE_CONFIG"
    ][0]).operations.ensure_physical_database_instance.terraform.moduleSelectors.postgres.inputs.database_infrastructure.scale_to_zero == false
    error_message = "App Databases must keep physical databases active by default."
  }
}

run "scale_to_zero_true_reaches_the_physical_module" {
  command = plan

  variables {
    database_infrastructure = {
      scale_to_zero = true
    }
  }

  assert {
    condition = jsondecode([
      for env in output.ecs_env_vars : env.value
      if env.name == "SUPERBLOCKS_DATABASE_LIFECYCLE_CONFIG"
    ][0]).operations.ensure_physical_database_instance.terraform.moduleSelectors.postgres.inputs.database_infrastructure.scale_to_zero == true
    error_message = "The App Databases scale_to_zero setting must reach the shared physical module unchanged."
  }
}

run "the_beta_always_selects_aurora" {
  command = plan

  assert {
    condition = jsondecode([
      for env in output.ecs_env_vars : env.value
      if env.name == "SUPERBLOCKS_DATABASE_LIFECYCLE_CONFIG"
    ][0]).operations.ensure_physical_database_instance.terraform.moduleSelectors.postgres.source == "./modules/aws-aurora-managed-cluster"
    error_message = "The App Databases beta must always select the Aurora physical module."
  }
}

run "low_level_aurora_capacity_overrides_are_rejected" {
  command = plan

  variables {
    physical_module_inputs = {
      deployment = {
        serverless_v2 = {
          max_acu = 64
        }
      }
      monitoring_role_arn = "arn:aws:iam::123456789012:role/sb-app-db-enhanced-monitoring"
      subnet_ids          = ["subnet-0000000000000001", "subnet-0000000000000002"]
      vpc_id              = "vpc-0123456789abcdef0"
    }
  }

  expect_failures = [var.physical_module_inputs]
}

run "standalone_rds_selection_is_rejected" {
  command = plan

  variables {
    physical_module_inputs = {
      allocated_storage   = 100
      instance_class      = "db.t4g.medium"
      monitoring_role_arn = "arn:aws:iam::123456789012:role/sb-app-db-enhanced-monitoring"
      subnet_ids          = ["subnet-0000000000000001", "subnet-0000000000000002"]
      vpc_id              = "vpc-0123456789abcdef0"
    }
  }

  expect_failures = [var.physical_module_inputs]
}

run "configuration_change_warning_is_an_output" {
  command = plan

  assert {
    condition     = output.database_infrastructure_notice == "WARNING: Changing scale_to_zero after App Databases have been provisioned does not update existing physical databases automatically. Contact Superblocks Support to update existing databases and avoid mixed configurations."
    error_message = "The module must expose the App Databases reconciliation warning as an output."
  }
}
