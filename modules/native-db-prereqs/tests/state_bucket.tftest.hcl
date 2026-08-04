# Shared state bucket: each worker may only touch native-db/<agent>/. Without a
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
}

variables {
  deployment_type = "fargate"
  region          = "us-east-1"

  agents = {
    opa1 = {
      agent_tags = ["nonprod"]
      vpc_id     = "vpc-0123456789abcdef0"
    }
    opa2 = {
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
      ]) == "${aws_s3_bucket.tofu_state.arn}/native-db/${name}/*"
    ])
    error_message = "Each worker's object access must be limited to native-db/<agent>/*, not the whole bucket."
  }

  assert {
    condition = alltrue([
      for name in keys(var.agents) :
      one([
        for statement in jsondecode(aws_iam_policy.lifecycle_worker_state_bucket[name].policy).Statement :
        statement.Condition.StringLike["s3:prefix"] if statement.Sid == "StateBucketList"
      ]) == ["native-db/${name}", "native-db/${name}/*"]
    ])
    error_message = "ListBucket must require s3:prefix under native-db/<agent>/."
  }

  assert {
    condition = !contains([
      for statement in jsondecode(aws_iam_policy.lifecycle_worker_state_bucket["opa1"].policy).Statement :
      try(statement.Sid, "")
    ], "StateBucketKms")
    error_message = "Without kms_key_arn the policy must not grant KMS permissions."
  }

  assert {
    condition     = output.agents["opa1"].key_prefix == "native-db/opa1"
    error_message = "agents[].key_prefix must match the IAM-granted state prefix."
  }
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
