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
  connector_role_arn = "arn:aws:iam::123456789012:role/sb-app-db-opa1-connector"
  region             = "us-east-1"
  state_bucket_name  = "sb-app-db-us-east-1-123456789012"

  physical_module_inputs = {
    monitoring_role_arn = "arn:aws:iam::123456789012:role/sb-app-db-enhanced-monitoring"
    subnet_ids          = ["subnet-0000000000000001", "subnet-0000000000000002"]
    vpc_id              = "vpc-0123456789abcdef0"
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
      monitoring_role_arn = "arn:aws:iam::123456789012:role/sb-app-db-enhanced-monitoring"
      subnet_ids          = ["subnet-0000000000000001", "subnet-0000000000000002"]
      vpc_id              = "vpc-0123456789abcdef0"
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
      allocated_storage   = 100
      instance_class      = "db.t4g.medium"
      monitoring_role_arn = "arn:aws:iam::123456789012:role/sb-app-db-enhanced-monitoring"
      subnet_ids          = ["subnet-0000000000000001", "subnet-0000000000000002"]
      vpc_id              = "vpc-0123456789abcdef0"
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
      instance_class      = "db.t4g.medium"
      monitoring_role_arn = "arn:aws:iam::123456789012:role/sb-app-db-enhanced-monitoring"
      subnet_ids          = ["subnet-0000000000000001", "subnet-0000000000000002"]
      vpc_id              = "vpc-0123456789abcdef0"
    }
  }

  expect_failures = [var.physical_module_inputs]
}

run "aurora_capacity_and_rds_sizing_cannot_be_combined" {
  command = plan

  variables {
    physical_module_inputs = {
      allocated_storage   = 100
      deployment          = { serverless_v2 = { max_acu = 8 } }
      instance_class      = "db.t4g.medium"
      monitoring_role_arn = "arn:aws:iam::123456789012:role/sb-app-db-enhanced-monitoring"
      subnet_ids          = ["subnet-0000000000000001", "subnet-0000000000000002"]
      vpc_id              = "vpc-0123456789abcdef0"
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
      monitoring_role_arn = "arn:aws:iam::123456789012:role/sb-app-db-enhanced-monitoring"
      subnet_ids          = ["subnet-0000000000000001", "subnet-0000000000000002"]
      vpc_id              = "vpc-0123456789abcdef0"
    }
  }

  expect_failures = [var.physical_module_inputs]
}

run "an_empty_aurora_deployment_is_rejected_rather_than_silently_defaulted" {
  command = plan

  variables {
    physical_module_inputs = {
      deployment          = {}
      monitoring_role_arn = "arn:aws:iam::123456789012:role/sb-app-db-enhanced-monitoring"
      subnet_ids          = ["subnet-0000000000000001", "subnet-0000000000000002"]
      vpc_id              = "vpc-0123456789abcdef0"
    }
  }

  expect_failures = [var.physical_module_inputs]
}

# Both physical modules default monitoring_interval to 60 and reject that
# without a role, so the rendered inputs have to carry the pair or no database
# ever provisions.
run "enhanced_monitoring_reaches_both_physical_modules" {
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

run "allocated_storage_must_be_positive" {
  command = plan

  variables {
    physical_module_inputs = {
      allocated_storage   = 0
      instance_class      = "db.t4g.medium"
      monitoring_role_arn = "arn:aws:iam::123456789012:role/sb-app-db-enhanced-monitoring"
      subnet_ids          = ["subnet-0000000000000001", "subnet-0000000000000002"]
      vpc_id              = "vpc-0123456789abcdef0"
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

run "multi_az_alone_cannot_select_rds" {
  command = plan

  variables {
    physical_module_inputs = {
      monitoring_role_arn = "arn:aws:iam::123456789012:role/sb-app-db-enhanced-monitoring"
      multi_az            = true
      subnet_ids          = ["subnet-0000000000000001", "subnet-0000000000000002"]
      vpc_id              = "vpc-0123456789abcdef0"
    }
  }

  expect_failures = [var.physical_module_inputs]
}

run "deployment_and_multi_az_cannot_be_combined" {
  command = plan

  variables {
    physical_module_inputs = {
      deployment = {
        serverless_v2 = {}
      }
      monitoring_role_arn = "arn:aws:iam::123456789012:role/sb-app-db-enhanced-monitoring"
      multi_az            = true
      subnet_ids          = ["subnet-0000000000000001", "subnet-0000000000000002"]
      vpc_id              = "vpc-0123456789abcdef0"
    }
  }

  expect_failures = [var.physical_module_inputs]
}
