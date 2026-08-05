# The connector role's rds-db:connect grant has to name the DB users the
# lifecycle worker actually creates. The worker derives the profile segment of
# every database and runtime user from the data tag by hashing it — first 16 hex
# characters of SHA-256 over the lowercased tag — so a policy written against the
# bare tag matches nothing and every query fails with AccessDenied.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  # Generated mock IDs are not ARN-shaped, and the provider validates the
  # policy_arn it is handed before any assertion runs.
  mock_resource "aws_iam_policy" {
    defaults = {
      arn = "arn:aws:iam::123456789012:policy/mock"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/mock"
    }
  }
}

variables {
  deployment_type = "fargate"
  region          = "us-east-1"

  agents = {
    prod = {
      agent_tags = ["nonprod", "production"]
      vpc_id     = "vpc-0123456789abcdef0"
    }
  }
}

run "the_connect_grant_names_hashed_profile_tokens" {
  command = plan

  # printf '%s' nonprod | shasum -a 256 | cut -c1-16
  assert {
    condition = contains(
      flatten([for statement in jsondecode(aws_iam_policy.connector["prod"].policy).Statement : statement.Resource]),
      "arn:aws:rds-db:us-east-1:123456789012:dbuser:cluster-*/sbndb_6fdc0c6b96ee8a74_*_runtime"
    )
    error_message = "The Aurora grant for the nonprod tag must name the hashed profile token 6fdc0c6b96ee8a74."
  }

  assert {
    condition = contains(
      flatten([for statement in jsondecode(aws_iam_policy.connector["prod"].policy).Statement : statement.Resource]),
      "arn:aws:rds-db:us-east-1:123456789012:dbuser:db-*/sbndb_6fdc0c6b96ee8a74_*_runtime"
    )
    error_message = "The standalone RDS grant for the nonprod tag must name the hashed profile token 6fdc0c6b96ee8a74."
  }

  # printf '%s' production | shasum -a 256 | cut -c1-16
  assert {
    condition = contains(
      flatten([for statement in jsondecode(aws_iam_policy.connector["prod"].policy).Statement : statement.Resource]),
      "arn:aws:rds-db:us-east-1:123456789012:dbuser:cluster-*/sbndb_ab8e18ef4ebebedd_*_runtime"
    )
    error_message = "The Aurora grant for the production tag must name the hashed profile token ab8e18ef4ebebedd."
  }

  assert {
    condition = alltrue([
      for resource in flatten([for statement in jsondecode(aws_iam_policy.connector["prod"].policy).Statement : statement.Resource]) :
      can(regex("/sbndb_[0-9a-f]{16}_\\*_runtime$", resource))
    ])
    error_message = "Every grant must target the sbndb_<16 hex>_<application token>_runtime namespace the worker creates; a bare data tag matches no DB user."
  }

  # The Sid stays human-readable so an operator can map a statement back to the
  # tag that produced it — only the DB user namespace is hashed.
  assert {
    condition = [
      for statement in jsondecode(aws_iam_policy.connector["prod"].policy).Statement : statement.Sid
    ] == ["ConnectTagNonprod", "ConnectTagProduction"]
    error_message = "Statement Sids must name the data tag they came from."
  }
}

run "the_tags_output_matches_what_the_module_stamps" {
  command = plan

  variables {
    tags = { Environment = "production" }
  }

  # The example forwards this output into physical_module_inputs.tags, so it has
  # to be the merged set the module puts on its own resources, not the caller's
  # raw input.
  assert {
    condition     = tomap(output.tags) == aws_iam_role.lifecycle_worker["prod"].tags
    error_message = "The tags output must equal the tags the module applies to the resources it creates."
  }

  assert {
    condition     = output.tags == { Environment = "production", ManagedBy = "superblocks-app-database-lifecycle" }
    error_message = "The tags output must merge ManagedBy over the caller's tags."
  }
}
