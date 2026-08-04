# Lifecycle workers share one S3 state bucket per region. Object and list
# permissions must be scoped to native-db/<agent>/ so one compromised worker
# cannot read or overwrite another agent's OpenTofu state. When no customer
# CMK is configured the bucket uses SSE-S3, so the policy must not grant
# Resource:* KMS decrypt via CalledVia.

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

run "object_access_is_scoped_to_each_agents_state_prefix" {
  command = plan

  assert {
    condition = [
      for statement in jsondecode(aws_iam_policy.lifecycle_worker_state_bucket["opa1"].policy).Statement :
      statement.Resource if statement.Sid == "StateBucketObjectReadWrite"
    ][0] == "${aws_s3_bucket.tofu_state.arn}/native-db/opa1/*"
    error_message = "opa1 object access must be limited to native-db/opa1/*, not the whole bucket."
  }

  assert {
    condition = [
      for statement in jsondecode(aws_iam_policy.lifecycle_worker_state_bucket["opa2"].policy).Statement :
      statement.Resource if statement.Sid == "StateBucketObjectReadWrite"
    ][0] == "${aws_s3_bucket.tofu_state.arn}/native-db/opa2/*"
    error_message = "opa2 object access must be limited to native-db/opa2/*, not the whole bucket."
  }
}

run "list_bucket_is_constrained_to_each_agents_state_prefix" {
  command = plan

  assert {
    condition = [
      for statement in jsondecode(aws_iam_policy.lifecycle_worker_state_bucket["opa1"].policy).Statement :
      statement.Condition.StringLike["s3:prefix"] if statement.Sid == "StateBucketList"
    ][0] == ["native-db/opa1", "native-db/opa1/*"]
    error_message = "ListBucket for opa1 must require s3:prefix under native-db/opa1."
  }

  assert {
    condition = !contains(
      [
        for statement in jsondecode(aws_iam_policy.lifecycle_worker_state_bucket["opa1"].policy).Statement :
        statement.Sid if contains(statement.Action, "s3:GetBucketLocation")
      ],
      "StateBucketList"
    )
    error_message = "GetBucketLocation must not share the ListBucket prefix condition, or metadata calls fail closed."
  }
}

run "kms_permissions_are_omitted_when_no_customer_managed_key_is_set" {
  command = plan

  assert {
    condition = !contains(
      [
        for statement in jsondecode(aws_iam_policy.lifecycle_worker_state_bucket["opa1"].policy).Statement :
        try(statement.Sid, "")
      ],
      "StateBucketKms"
    )
    error_message = "Without kms_key_arn the bucket uses SSE-S3; the policy must not grant KMS Resource:*."
  }
}

run "kms_permissions_are_scoped_to_the_customer_managed_key_when_set" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/mrk-test"
  }

  assert {
    condition = [
      for statement in jsondecode(aws_iam_policy.lifecycle_worker_state_bucket["opa1"].policy).Statement :
      statement.Resource if statement.Sid == "StateBucketKms"
    ][0] == "arn:aws:kms:us-east-1:123456789012:key/mrk-test"
    error_message = "State-bucket KMS actions must name the configured customer-managed key."
  }
}

run "agents_output_exposes_the_state_key_prefix_iam_grants" {
  command = plan

  assert {
    condition     = output.agents["opa1"].key_prefix == "native-db/opa1"
    error_message = "agents[opa1].key_prefix must match the IAM-granted state prefix so native-db can wire it without drift."
  }

  assert {
    condition     = output.agents["opa2"].key_prefix == "native-db/opa2"
    error_message = "agents[opa2].key_prefix must match the IAM-granted state prefix so native-db can wire it without drift."
  }
}
