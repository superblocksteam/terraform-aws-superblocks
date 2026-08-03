# Which physical database a caller gets, and which capacity arguments reach it.
# Aurora Serverless v2 is what a caller gets without asking; Aurora provisioned
# and standalone RDS are opt-in. Each physical module rejects the other's
# capacity arguments, so a mode must never forward the other mode's inputs.

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
  connector_role_arn = "arn:aws:iam::123456789012:role/sb-native-db-opa1-connector"
  key_prefix         = "native-db/opa1"
  region             = "us-east-1"
  state_bucket_name  = "sb-native-db-us-east-1-123456789012"

  physical_module_inputs = {
    subnet_ids = ["subnet-0000000000000001", "subnet-0000000000000002"]
    vpc_id     = "vpc-0123456789abcdef0"
  }
}

run "a_caller_that_names_no_capacity_gets_aurora_serverless" {
  command = plan

  assert {
    condition = jsondecode([
      for env in output.ecs_env_vars : env.value
      if env.name == "SUPERBLOCKS_DATABASE_LIFECYCLE_CONFIG"
    ][0]).operations.ensure_physical_database_instance.terraform.moduleSelectors.postgres.source == "./modules/aws-aurora-managed-cluster"
    error_message = "The default physical module must be the Aurora cluster, not standalone RDS."
  }

  assert {
    condition = can(jsondecode([
      for env in output.ecs_env_vars : env.value
      if env.name == "SUPERBLOCKS_DATABASE_LIFECYCLE_CONFIG"
    ][0]).operations.ensure_physical_database_instance.terraform.moduleSelectors.postgres.inputs.deployment.serverless_v2)
    error_message = "An omitted deployment must still ask Aurora for Serverless v2 capacity."
  }

  assert {
    condition = !contains(keys(jsondecode([
      for env in output.ecs_env_vars : env.value
      if env.name == "SUPERBLOCKS_DATABASE_LIFECYCLE_CONFIG"
    ][0]).operations.ensure_physical_database_instance.terraform.moduleSelectors.postgres.inputs), "allocated_storage")
    error_message = "Aurora has no allocated_storage variable; forwarding it fails the plan with Unsupported argument."
  }

  assert {
    condition = [
      for env in output.ecs_env_vars : env.value
      if env.name == "SUPERBLOCKS_DATABASE_LIFECYCLE_ALLOWED_MODULE_SOURCES"
    ][0] == "./modules/postgres-managed-database,./modules/aws-aurora-managed-cluster"
    error_message = "The module-source allowlist must name the physical module this OPA actually dispatches."
  }
}

run "a_caller_can_ask_aurora_for_provisioned_instances" {
  command = plan

  variables {
    physical_module_inputs = {
      deployment = {
        provisioned = {
          instance_class = "db.r6g.xlarge"
          instance_count = 3
        }
      }
      subnet_ids = ["subnet-0000000000000001", "subnet-0000000000000002"]
      vpc_id     = "vpc-0123456789abcdef0"
    }
  }

  assert {
    condition = jsondecode([
      for env in output.ecs_env_vars : env.value
      if env.name == "SUPERBLOCKS_DATABASE_LIFECYCLE_CONFIG"
    ][0]).operations.ensure_physical_database_instance.terraform.moduleSelectors.postgres.source == "./modules/aws-aurora-managed-cluster"
    error_message = "Provisioned capacity is an Aurora deployment shape, so it must still select the Aurora module."
  }

  assert {
    condition = jsondecode([
      for env in output.ecs_env_vars : env.value
      if env.name == "SUPERBLOCKS_DATABASE_LIFECYCLE_CONFIG"
    ][0]).operations.ensure_physical_database_instance.terraform.moduleSelectors.postgres.inputs.deployment.provisioned.instance_class == "db.r6g.xlarge"
    error_message = "A provisioned instance class must reach the Aurora module unchanged."
  }
}

run "a_caller_can_ask_for_standalone_rds_by_sizing_an_instance" {
  command = plan

  variables {
    physical_module_inputs = {
      allocated_storage = 100
      instance_class    = "db.t4g.medium"
      subnet_ids        = ["subnet-0000000000000001", "subnet-0000000000000002"]
      vpc_id            = "vpc-0123456789abcdef0"
    }
  }

  assert {
    condition = jsondecode([
      for env in output.ecs_env_vars : env.value
      if env.name == "SUPERBLOCKS_DATABASE_LIFECYCLE_CONFIG"
    ][0]).operations.ensure_physical_database_instance.terraform.moduleSelectors.postgres.source == "./modules/aws-rds-managed-instance"
    error_message = "Instance sizing is RDS-only, so it must select the RDS instance module."
  }

  assert {
    condition = jsondecode([
      for env in output.ecs_env_vars : env.value
      if env.name == "SUPERBLOCKS_DATABASE_LIFECYCLE_CONFIG"
    ][0]).operations.ensure_physical_database_instance.terraform.moduleSelectors.postgres.inputs.allocated_storage == 100
    error_message = "Allocated storage must reach the RDS module unchanged."
  }

  assert {
    condition = !contains(keys(jsondecode([
      for env in output.ecs_env_vars : env.value
      if env.name == "SUPERBLOCKS_DATABASE_LIFECYCLE_CONFIG"
    ][0]).operations.ensure_physical_database_instance.terraform.moduleSelectors.postgres.inputs), "deployment")
    error_message = "RDS has no deployment variable; forwarding it fails the plan with Unsupported argument."
  }

  assert {
    condition = [
      for env in output.ecs_env_vars : env.value
      if env.name == "SUPERBLOCKS_DATABASE_LIFECYCLE_ALLOWED_MODULE_SOURCES"
    ][0] == "./modules/postgres-managed-database,./modules/aws-rds-managed-instance"
    error_message = "The module-source allowlist must follow the selected physical module."
  }
}

run "an_rds_instance_needs_both_sizing_inputs" {
  command = plan

  variables {
    physical_module_inputs = {
      instance_class = "db.t4g.medium"
      subnet_ids     = ["subnet-0000000000000001", "subnet-0000000000000002"]
      vpc_id         = "vpc-0123456789abcdef0"
    }
  }

  expect_failures = [var.physical_module_inputs]
}

run "aurora_capacity_and_rds_sizing_cannot_be_combined" {
  command = plan

  variables {
    physical_module_inputs = {
      allocated_storage = 100
      deployment        = { serverless_v2 = { max_acu = 8 } }
      instance_class    = "db.t4g.medium"
      subnet_ids        = ["subnet-0000000000000001", "subnet-0000000000000002"]
      vpc_id            = "vpc-0123456789abcdef0"
    }
  }

  expect_failures = [var.physical_module_inputs]
}

run "an_aurora_deployment_names_exactly_one_capacity_shape" {
  command = plan

  variables {
    physical_module_inputs = {
      deployment = {
        provisioned   = { instance_class = "db.r6g.large" }
        serverless_v2 = { max_acu = 8 }
      }
      subnet_ids = ["subnet-0000000000000001", "subnet-0000000000000002"]
      vpc_id     = "vpc-0123456789abcdef0"
    }
  }

  expect_failures = [var.physical_module_inputs]
}

run "an_empty_aurora_deployment_is_rejected_rather_than_silently_defaulted" {
  command = plan

  variables {
    physical_module_inputs = {
      deployment = {}
      subnet_ids = ["subnet-0000000000000001", "subnet-0000000000000002"]
      vpc_id     = "vpc-0123456789abcdef0"
    }
  }

  expect_failures = [var.physical_module_inputs]
}
