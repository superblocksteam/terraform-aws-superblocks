# The runtime configuration this module hands the OPA container. These
# assertions track contracts the lifecycle worker enforces at startup: a flat
# lifecycle document, profiles declared only through agent tags, and defaults
# the worker owns rather than the operator.

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
    monitoring_role_arn = "arn:aws:iam::123456789012:role/sb-native-db-enhanced-monitoring"
    subnet_ids          = ["subnet-0000000000000001", "subnet-0000000000000002"]
    vpc_id              = "vpc-0123456789abcdef0"
  }
}

run "the_lifecycle_document_is_one_flat_configuration" {
  command = plan

  assert {
    condition = alltrue([
      for key in keys(jsondecode([
        for env in output.ecs_env_vars : env.value
        if env.name == "SUPERBLOCKS_DATABASE_LIFECYCLE_CONFIG"
      ][0])) : contains(["engines", "operations"], key)
    ])
    error_message = "The worker rejects any key other than engines and operations, including entries and profiles."
  }

  assert {
    condition = jsondecode([
      for env in output.ecs_env_vars : env.value
      if env.name == "SUPERBLOCKS_DATABASE_LIFECYCLE_CONFIG"
    ][0]).engines == ["postgres"]
    error_message = "Engines must sit at the document root."
  }

  assert {
    condition = alltrue([
      for operation in ["ensure_database", "ensure_physical_database_instance", "migrate_schema", "retire_database"] :
      contains(keys(jsondecode([
        for env in output.ecs_env_vars : env.value
        if env.name == "SUPERBLOCKS_DATABASE_LIFECYCLE_CONFIG"
      ][0]).operations), operation)
    ])
    error_message = "Every operation this OPA serves must sit at the document root."
  }
}

run "profiles_are_declared_once_as_agent_tags" {
  command = plan

  assert {
    condition     = output.superblocks_agent_tags == "profile:nonprod,profile:production"
    error_message = "The module must derive the agent tag string so it cannot drift from the lifecycle config."
  }

  assert {
    condition = length([
      for env in output.ecs_env_vars : env.name
      if env.name == "SUPERBLOCKS_ORCHESTRATOR_AGENT_TAGS"
    ]) == 0
    error_message = "The root module already emits SUPERBLOCKS_ORCHESTRATOR_AGENT_TAGS; a second copy would leave the container with two values for one key."
  }
}

run "the_worker_owns_its_own_resource_type_allowlist" {
  command = plan

  assert {
    condition = length([
      for env in output.ecs_env_vars : env.name
      if env.name == "SUPERBLOCKS_DATABASE_LIFECYCLE_ALLOWED_RESOURCE_TYPES"
    ]) == 0
    error_message = "An operator-supplied allowlist replaces the worker default outright, so a hardcoded list breaks the first plan that creates a newly published resource type."
  }
}

run "the_logical_module_gets_only_the_inputs_it_still_declares" {
  command = plan

  assert {
    condition = !contains(keys(jsondecode([
      for env in output.ecs_env_vars : env.value
      if env.name == "SUPERBLOCKS_DATABASE_LIFECYCLE_CONFIG"
    ][0]).operations.ensure_database.terraform.moduleSelectors.postgres.inputs), "auth_mode")
    error_message = "The worker sends auth_mode itself; sending it here duplicates a value the module no longer accepts from operators."
  }

  assert {
    condition = jsondecode([
      for env in output.ecs_env_vars : env.value
      if env.name == "SUPERBLOCKS_DATABASE_LIFECYCLE_CONFIG"
    ][0]).operations.ensure_database.terraform.moduleSelectors.postgres.inputs.connector_role_arn == var.connector_role_arn
    error_message = "The worker only advertises managed IAM when the logical module inputs carry the connector role it was configured with."
  }
}
