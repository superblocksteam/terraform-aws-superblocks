# The data plane must be able to reach the clusters this module configures.
# The physical modules open port 5432 only to source_security_group_ids and
# allowed_cidr_blocks, and both default to empty, so a caller who sets neither
# provisions clusters nothing can connect to. The Helm chart already fails the
# render in that case (helm/agent: "physicalModuleInputs requires
# source_security_group_ids or allowed_cidr_blocks"); this module fails the plan
# the same way so Fargate does not discover the omission at the first query.

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
}

run "a_caller_that_names_no_source_is_rejected" {
  command = plan

  variables {
    physical_module_inputs = {
      monitoring_role_arn = "arn:aws:iam::123456789012:role/sb-app-db-enhanced-monitoring"
      subnet_ids          = ["subnet-0000000000000001", "subnet-0000000000000002"]
      vpc_id              = "vpc-0123456789abcdef0"
    }
  }

  expect_failures = [var.physical_module_inputs]
}

run "a_null_security_group_id_is_rejected" {
  command = plan

  # What a caller gets from the root module's ecs_security_group_id output when
  # create_ecs_sg = false. The list is non-empty, so a length check alone would
  # let it through to the physical module.
  variables {
    physical_module_inputs = {
      monitoring_role_arn       = "arn:aws:iam::123456789012:role/sb-app-db-enhanced-monitoring"
      source_security_group_ids = [null]
      subnet_ids                = ["subnet-0000000000000001", "subnet-0000000000000002"]
      vpc_id                    = "vpc-0123456789abcdef0"
    }
  }

  expect_failures = [var.physical_module_inputs]
}

run "the_data_plane_security_group_reaches_the_physical_module" {
  command = plan

  variables {
    physical_module_inputs = {
      monitoring_role_arn       = "arn:aws:iam::123456789012:role/sb-app-db-enhanced-monitoring"
      source_security_group_ids = ["sg-0123456789abcdef0"]
      subnet_ids                = ["subnet-0000000000000001", "subnet-0000000000000002"]
      vpc_id                    = "vpc-0123456789abcdef0"
    }
  }

  assert {
    condition = jsondecode([
      for env in output.ecs_env_vars : env.value
      if env.name == "SUPERBLOCKS_DATABASE_LIFECYCLE_CONFIG"
    ][0]).operations.ensure_physical_database_instance.terraform.moduleSelectors.postgres.inputs.source_security_group_ids == ["sg-0123456789abcdef0"]
    error_message = "The physical module must receive the caller's security group as its ingress source."
  }
}

run "cidr_blocks_alone_satisfy_reachability" {
  command = plan

  variables {
    physical_module_inputs = {
      allowed_cidr_blocks = ["10.0.0.0/16"]
      monitoring_role_arn = "arn:aws:iam::123456789012:role/sb-app-db-enhanced-monitoring"
      subnet_ids          = ["subnet-0000000000000001", "subnet-0000000000000002"]
      vpc_id              = "vpc-0123456789abcdef0"
    }
  }

  assert {
    condition = jsondecode([
      for env in output.ecs_env_vars : env.value
      if env.name == "SUPERBLOCKS_DATABASE_LIFECYCLE_CONFIG"
    ][0]).operations.ensure_physical_database_instance.terraform.moduleSelectors.postgres.inputs.allowed_cidr_blocks == ["10.0.0.0/16"]
    error_message = "The physical module must receive the caller's CIDR ranges as its ingress source."
  }
}
