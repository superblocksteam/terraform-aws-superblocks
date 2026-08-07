# Physical inputs that remain customer-configurable during the App Databases
# beta. Capacity and engine selection are covered by database_infrastructure
# contract tests; this file verifies the retained operational inputs.

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
    tags                = { Environment = "production" }
    vpc_id              = "vpc-0123456789abcdef0"
  }
}

run "supported_physical_inputs_reach_aurora" {
  command = plan

  assert {
    condition = jsondecode([
      for env in output.ecs_env_vars : env.value
      if env.name == "SUPERBLOCKS_DATABASE_LIFECYCLE_CONFIG"
    ][0]).operations.ensure_physical_database_instance.terraform.moduleSelectors.postgres.source == "./modules/aws-aurora-managed-cluster"
    error_message = "The App Databases beta must use the Aurora physical module."
  }

  assert {
    condition = jsondecode([
      for env in output.ecs_env_vars : env.value
      if env.name == "SUPERBLOCKS_DATABASE_LIFECYCLE_CONFIG"
    ][0]).operations.ensure_physical_database_instance.terraform.moduleSelectors.postgres.inputs.tags.Environment == "production"
    error_message = "Supported physical module tags must reach Aurora unchanged."
  }

  assert {
    condition = !contains(keys(jsondecode([
      for env in output.ecs_env_vars : env.value
      if env.name == "SUPERBLOCKS_DATABASE_LIFECYCLE_CONFIG"
    ][0]).operations.ensure_physical_database_instance.terraform.moduleSelectors.postgres.inputs), "deployment")
    error_message = "Low-level Aurora deployment settings must not reach the shared physical module."
  }

  assert {
    condition = [
      for env in output.ecs_env_vars : env.value
      if env.name == "SUPERBLOCKS_DATABASE_LIFECYCLE_ALLOWED_MODULE_SOURCES"
    ][0] == "./modules/postgres-managed-database,./modules/aws-aurora-managed-cluster"
    error_message = "The module-source allowlist must contain the fixed Aurora physical module."
  }
}

# The physical module defaults monitoring_interval to 60 and rejects that
# without a role, so the rendered inputs have to carry the pair or no database
# ever provisions.
run "enhanced_monitoring_reaches_the_physical_module" {
  command = plan

  assert {
    condition = jsondecode([
      for env in output.ecs_env_vars : env.value
      if env.name == "SUPERBLOCKS_DATABASE_LIFECYCLE_CONFIG"
    ][0]).operations.ensure_physical_database_instance.terraform.moduleSelectors.postgres.inputs.monitoring_role_arn == "arn:aws:iam::123456789012:role/sb-app-db-enhanced-monitoring"
    error_message = "The Aurora inputs must carry the Enhanced Monitoring role the caller supplied."
  }

  assert {
    condition = jsondecode([
      for env in output.ecs_env_vars : env.value
      if env.name == "SUPERBLOCKS_DATABASE_LIFECYCLE_CONFIG"
    ][0]).operations.ensure_physical_database_instance.terraform.moduleSelectors.postgres.inputs.monitoring_interval == 60
    error_message = "Enhanced Monitoring must stay on by default rather than relying on the physical module's own default."
  }
}

run "enhanced_monitoring_without_a_role_is_rejected_here_not_inside_the_worker" {
  command = plan

  variables {
    physical_module_inputs = {
      subnet_ids = ["subnet-0000000000000001", "subnet-0000000000000002"]
      vpc_id     = "vpc-0123456789abcdef0"
    }
  }

  expect_failures = [var.physical_module_inputs]
}

run "subnet_ids_need_at_least_two_availability_zones" {
  command = plan

  variables {
    physical_module_inputs = {
      monitoring_role_arn = "arn:aws:iam::123456789012:role/sb-app-db-enhanced-monitoring"
      subnet_ids          = ["subnet-0000000000000001"]
      vpc_id              = "vpc-0123456789abcdef0"
    }
  }

  expect_failures = [var.physical_module_inputs]
}

run "vpc_id_must_look_like_a_vpc_id" {
  command = plan

  variables {
    physical_module_inputs = {
      monitoring_role_arn = "arn:aws:iam::123456789012:role/sb-app-db-enhanced-monitoring"
      subnet_ids          = ["subnet-0000000000000001", "subnet-0000000000000002"]
      vpc_id              = "not-a-vpc-id"
    }
  }

  expect_failures = [var.physical_module_inputs]
}

# Agent names land in IAM role names and the worker's pool identity. Restrict
# to lowercase alphanumeric so later resources that reject hyphens/underscores
# do not force a rename after databases exist.
run "agent_name_rejects_hyphens" {
  command = plan

  variables {
    agent_name = "opa-1"
  }

  expect_failures = [var.agent_name]
}

run "agent_name_rejects_underscores" {
  command = plan

  variables {
    agent_name = "opa_1"
  }

  expect_failures = [var.agent_name]
}
