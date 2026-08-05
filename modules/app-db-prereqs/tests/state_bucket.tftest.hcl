# Shared state bucket: each worker may only touch app-db/<agent>/. Without a
# CMK the bucket is SSE-S3, so the policy must not attach a KMS Resource:*.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

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

  mock_resource "aws_s3_bucket" {
    defaults = {
      arn = "arn:aws:s3:::sb-app-db-us-east-1-123456789012"
      id  = "sb-app-db-us-east-1-123456789012"
    }
  }
}

variables {
  deployment_type = "fargate"
  region          = "us-east-1"

  agents = {
    opa1 = {
      agent_tags = ["nonprod"]
      vpc_id     = "vpc-0123456789abcdef0"
    }
    opa10 = {
      agent_tags = ["staging"]
      vpc_id     = "vpc-0fedcba9876543210"
    }
  }
}

run "state_access_is_scoped_per_agent" {
  command = plan

  assert {
    condition = alltrue([
      for name in keys(var.agents) :
      one([
        for statement in jsondecode(aws_iam_policy.lifecycle_worker_state_bucket[name].policy).Statement :
        statement.Resource if statement.Sid == "StateBucketObjectReadWrite"
      ]) == "arn:aws:s3:::sb-app-db-us-east-1-123456789012/app-db/${name}/*"
    ])
    error_message = "Each worker's object access must be limited to app-db/<agent>/*, not the whole bucket."
  }

  assert {
    condition = alltrue([
      for name in keys(var.agents) :
      one([
        for statement in jsondecode(aws_iam_policy.lifecycle_worker_state_bucket[name].policy).Statement :
        statement.Condition.StringLike["s3:prefix"] if statement.Sid == "StateBucketList"
      ]) == ["app-db/${name}/", "app-db/${name}/*"]
    ])
    error_message = "ListBucket must require slash-bounded s3:prefix under app-db/<agent>/."
  }

  assert {
    condition = !contains([
      for statement in jsondecode(aws_iam_policy.lifecycle_worker_state_bucket["opa1"].policy).Statement :
      try(statement.Sid, "")
    ], "StateBucketKms")
    error_message = "Without kms_key_arn the policy must not grant KMS permissions."
  }

  assert {
    condition     = output.agents["opa1"].key_prefix == "app-db/opa1"
    error_message = "agents[].key_prefix must match the IAM-granted state prefix."
  }
}

run "list_prefix_does_not_collide_across_agent_name_prefixes" {
  command = plan

  assert {
    condition = one([
      for statement in jsondecode(aws_iam_policy.lifecycle_worker_state_bucket["opa1"].policy).Statement :
      statement.Condition.StringLike["s3:prefix"] if statement.Sid == "StateBucketList"
    ]) == ["app-db/opa1/", "app-db/opa1/*"]
    error_message = "opa1 must not allow the bare app-db/opa1 prefix that would enumerate opa10 keys."
  }

  assert {
    condition = one([
      for statement in jsondecode(aws_iam_policy.lifecycle_worker_state_bucket["opa10"].policy).Statement :
      statement.Condition.StringLike["s3:prefix"] if statement.Sid == "StateBucketList"
    ]) == ["app-db/opa10/", "app-db/opa10/*"]
    error_message = "opa10 ListBucket prefixes must stay slash-bounded under app-db/opa10/."
  }
}

run "a_caller_can_name_its_own_prefix" {
  command = plan

  variables {
    agents = {
      opa1 = {
        agent_tags = ["nonprod"]
        key_prefix = "custom/prod-db1"
        vpc_id     = "vpc-0123456789abcdef0"
      }
      opa10 = {
        agent_tags = ["staging"]
        vpc_id     = "vpc-0fedcba9876543210"
      }
    }
  }

  assert {
    condition = one([
      for statement in jsondecode(aws_iam_policy.lifecycle_worker_state_bucket["opa1"].policy).Statement :
      statement.Condition.StringLike["s3:prefix"] if statement.Sid == "StateBucketList"
    ]) == ["custom/prod-db1/", "custom/prod-db1/*"]
    error_message = "IAM must be scoped to the caller's prefix, not app-db/<agent>."
  }

  assert {
    condition     = output.agents["opa1"].key_prefix == "custom/prod-db1"
    error_message = "The output the app-db module consumes must carry the caller's prefix."
  }

  assert {
    condition     = output.agents["opa10"].key_prefix == "app-db/opa10"
    error_message = "An agent that names no prefix must keep the app-db/<agent> default."
  }
}

run "overlapping_prefixes_are_rejected" {
  command = plan

  variables {
    agents = {
      opa1 = {
        agent_tags = ["nonprod"]
        key_prefix = "app-db/shared"
        vpc_id     = "vpc-0123456789abcdef0"
      }
      opa10 = {
        agent_tags = ["staging"]
        key_prefix = "app-db/shared/nested"
        vpc_id     = "vpc-0fedcba9876543210"
      }
    }
  }

  expect_failures = [var.agents]
}

run "kms_is_scoped_to_the_configured_key" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/mrk-test"
  }

  assert {
    condition = one([
      for statement in jsondecode(aws_iam_policy.lifecycle_worker_state_bucket["opa1"].policy).Statement :
      statement.Resource if statement.Sid == "StateBucketKms"
    ]) == "arn:aws:kms:us-east-1:123456789012:key/mrk-test"
    error_message = "State-bucket KMS actions must name the configured customer-managed key."
  }
}
