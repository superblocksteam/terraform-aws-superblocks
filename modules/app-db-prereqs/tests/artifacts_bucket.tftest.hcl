# Artifacts bucket: long-lived (prevent_destroy), CORS must expose ETag,
# incomplete multipart uploads abort after seven days, and a dedicated
# lifecycle-worker policy must be able to sign/get/delete plus kms:Decrypt
# when a CMK is configured. One bucket is shared by every agent;
# artifacts_key_prefix and profile token separate their grants.

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
      arn = "arn:aws:s3:::mock"
      id  = "mock"
    }
  }
}

override_resource {
  target = aws_s3_bucket.artifacts
  values = {
    arn = "arn:aws:s3:::sb-data-artifacts-us-east-1-123456789012"
    id  = "sb-data-artifacts-us-east-1-123456789012"
  }
}

variables {
  allowed_origins = ["https://app.superblocks.com"]
  deployment_type = "fargate"
  region          = "us-east-1"

  agents = {
    opa1 = {
      agent_tags = ["nonprod"]
      vpc_id     = "vpc-0123456789abcdef0"
    }
  }
}

run "bucket_name_follows_prefix_then_region_then_account" {
  command = plan

  assert {
    condition     = aws_s3_bucket.artifacts.bucket == "sb-data-artifacts-us-east-1-123456789012"
    error_message = "The artifacts bucket must default to sb-data-artifacts-<region>-<account_id>."
  }

  assert {
    condition     = output.artifacts_bucket_name == "sb-data-artifacts-us-east-1-123456789012"
    error_message = "artifacts_bucket_name must be the bucket id."
  }

  assert {
    condition     = output.agents["opa1"].artifacts_key_prefix == ""
    error_message = "artifacts.keyPrefix is an optional namespace and is empty when unset."
  }
}

run "each_instantiation_can_name_its_own_bucket" {
  command = plan

  variables {
    s3_artifacts_name_prefix = "acme-data-artifacts"
  }

  assert {
    condition     = aws_s3_bucket.artifacts.bucket == "acme-data-artifacts-us-east-1-123456789012"
    error_message = "s3_artifacts_name_prefix must name the bucket so instantiations sharing an account do not collide."
  }

  assert {
    condition     = aws_s3_bucket.tofu_state.bucket == "sb-app-db-us-east-1-123456789012"
    error_message = "The artifacts prefix must not rename the state bucket, which carries prevent_destroy."
  }
}

run "artifacts_prefix_over_twenty_characters_is_rejected" {
  command = plan

  variables {
    s3_artifacts_name_prefix = "sb-data-artifacts-toolong"
  }

  expect_failures = [var.s3_artifacts_name_prefix]
}

run "cors_exposes_etag_for_multipart" {
  command = plan

  assert {
    condition     = contains(one(aws_s3_bucket_cors_configuration.artifacts[0].cors_rule).expose_headers, "ETag")
    error_message = "CORS must expose ETag so the browser can complete multipart uploads."
  }

  assert {
    condition     = one(aws_s3_bucket_cors_configuration.artifacts[0].cors_rule).allowed_methods == toset(["PUT"])
    error_message = "CORS must allow PUT; the worker initiates and completes multipart server-side."
  }

  assert {
    condition     = one(aws_s3_bucket_cors_configuration.artifacts[0].cors_rule).allowed_origins == toset(["https://app.superblocks.com"])
    error_message = "CORS allowed_origins must come from the caller variable."
  }
}

run "incomplete_multipart_uploads_abort_after_seven_days" {
  command = plan

  assert {
    condition     = one(aws_s3_bucket_lifecycle_configuration.artifacts.rule).abort_incomplete_multipart_upload[0].days_after_initiation == 7
    error_message = "Incomplete multipart uploads must be aborted after seven days."
  }

  assert {
    condition     = length(one(aws_s3_bucket_lifecycle_configuration.artifacts.rule).expiration) == 0
    error_message = "The multipart safety net must not expire completed artifacts."
  }
}

run "public_access_is_blocked" {
  command = plan

  assert {
    condition = (
      aws_s3_bucket_public_access_block.artifacts.block_public_acls &&
      aws_s3_bucket_public_access_block.artifacts.block_public_policy &&
      aws_s3_bucket_public_access_block.artifacts.ignore_public_acls &&
      aws_s3_bucket_public_access_block.artifacts.restrict_public_buckets
    )
    error_message = "The artifacts bucket must block all public access, matching the state bucket."
  }

  assert {
    condition = (
      one([
        for statement in jsondecode(aws_s3_bucket_policy.artifacts.policy).Statement :
        statement if statement.Sid == "DenyInsecureTransport"
      ]).Effect == "Deny" &&
      one([
        for statement in jsondecode(aws_s3_bucket_policy.artifacts.policy).Statement :
        statement if statement.Sid == "DenyInsecureTransport"
      ]).Condition.Bool["aws:SecureTransport"] == "false" &&
      toset(flatten([
        one([
          for statement in jsondecode(aws_s3_bucket_policy.artifacts.policy).Statement :
          statement.Resource if statement.Sid == "DenyInsecureTransport"
        ])
        ])) == toset([
        "arn:aws:s3:::sb-data-artifacts-us-east-1-123456789012",
        "arn:aws:s3:::sb-data-artifacts-us-east-1-123456789012/*",
      ])
    )
    error_message = "The artifacts bucket must deny requests that are not HTTPS."
  }
}

run "object_access_is_scoped_to_the_agent_profile_token" {
  command = plan

  assert {
    condition = alltrue([
      for statement in jsondecode(aws_iam_policy.connector["opa1"].policy).Statement :
      statement.Action == "rds-db:connect"
    ])
    error_message = "The connector policy must remain limited to rds-db:connect."
  }

  # printf '%s' nonprod | shasum -a 256 | cut -c1-16 => 6fdc0c6b96ee8a74
  assert {
    condition = one([
      for statement in jsondecode(aws_iam_policy.artifacts["opa1"].policy).Statement :
      statement.Resource if statement.Sid == "ArtifactsBucketObjectReadWrite"
    ]) == ["arn:aws:s3:::sb-data-artifacts-us-east-1-123456789012/6fdc0c6b96ee8a74/*"]
    error_message = "Object access must be limited to <profileToken>/*, covering every kind without a Terraform re-apply."
  }

  assert {
    condition = contains(
      one([
        for statement in jsondecode(aws_iam_policy.artifacts["opa1"].policy).Statement :
        statement.Action if statement.Sid == "ArtifactsBucketObjectReadWrite"
      ]),
      "s3:PutObject"
    )
    error_message = "The worker must be able to sign PUT URLs."
  }

  assert {
    condition = alltrue([
      for action in ["s3:DeleteObject", "s3:GetObject"] :
      contains(
        one([
          for statement in jsondecode(aws_iam_policy.artifacts["opa1"].policy).Statement :
          statement.Action if statement.Sid == "ArtifactsBucketObjectReadWrite"
        ]),
        action
      )
    ])
    error_message = "The worker must GetObject and DeleteObject under the prefix."
  }

  assert {
    condition = toset(flatten([
      one([
        for statement in jsondecode(aws_iam_policy.artifacts["opa1"].policy).Statement :
        statement.Action if statement.Sid == "ArtifactsBucketList"
      ])
    ])) == toset(["s3:ListBucket"])
    error_message = "ArtifactsBucketList must grant only ListBucket."
  }

  assert {
    condition     = aws_iam_role_policy_attachment.lifecycle_worker_artifacts["opa1"].policy_arn == aws_iam_policy.artifacts["opa1"].arn
    error_message = "The dedicated artifacts policy must be attached to the lifecycle worker."
  }

  assert {
    condition = !contains([
      for statement in jsondecode(aws_iam_policy.artifacts["opa1"].policy).Statement :
      try(statement.Sid, "")
    ], "ArtifactsBucketKms")
    error_message = "Without artifacts_kms_key_arn the policy must not grant KMS permissions."
  }
}

run "kms_decrypt_is_granted_when_a_customer_managed_key_is_set" {
  command = plan

  variables {
    artifacts_kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/mrk-artifacts"
  }

  assert {
    condition = one([
      for statement in jsondecode(aws_iam_policy.artifacts["opa1"].policy).Statement :
      statement.Resource if statement.Sid == "ArtifactsBucketKms"
    ]) == "arn:aws:kms:us-east-1:123456789012:key/mrk-artifacts"
    error_message = "Artifacts KMS actions must name the configured customer-managed key."
  }

  assert {
    condition = toset(flatten([
      one([
        for statement in jsondecode(aws_iam_policy.artifacts["opa1"].policy).Statement :
        statement.Action if statement.Sid == "ArtifactsBucketKms"
      ])
    ])) == toset(["kms:Decrypt", "kms:DescribeKey", "kms:GenerateDataKey"])
    error_message = "Artifacts KMS must be limited to Decrypt, DescribeKey, and GenerateDataKey."
  }

  assert {
    condition = one([
      for r in one(aws_s3_bucket_server_side_encryption_configuration.artifacts).rule :
      r.bucket_key_enabled
    ]) == true
    error_message = "SSE-KMS on artifacts must use a bucket key."
  }
}

run "a_state_bucket_key_does_not_encrypt_artifacts" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/mrk-state"
  }

  assert {
    condition = !contains([
      for statement in jsondecode(aws_iam_policy.artifacts["opa1"].policy).Statement :
      try(statement.Sid, "")
    ], "ArtifactsBucketKms")
    error_message = "kms_key_arn must not grant decrypt on artifact objects."
  }

  assert {
    condition     = length(aws_s3_bucket_server_side_encryption_configuration.artifacts) == 0
    error_message = "The artifacts bucket must stay on SSE-S3 unless artifacts_kms_key_arn is set."
  }
}

run "http_origins_are_rejected" {
  command = plan

  variables {
    allowed_origins = ["http://localhost:3000"]
  }

  expect_failures = [var.allowed_origins]
}

run "wildcard_origins_are_rejected" {
  command = plan

  variables {
    allowed_origins = ["https://*.example.com"]
  }

  expect_failures = [var.allowed_origins]
}

run "cors_is_optional_for_existing_callers" {
  command = plan

  variables {
    allowed_origins = []
  }

  assert {
    condition     = length(aws_s3_bucket_cors_configuration.artifacts) == 0
    error_message = "An empty allowed_origins list must omit CORS configuration."
  }
}

# A second agent shares the one bucket and namespaces itself with
# artifacts.keyPrefix. Keys are team-a/<profileToken>/<kind>/... The other
# agent leaves the prefix unset and writes <profileToken>/<kind>/...
run "an_agent_can_name_its_own_key_prefix" {
  command = plan

  variables {
    agents = {
      opa1 = {
        agent_tags           = ["nonprod"]
        artifacts_key_prefix = "team-a"
        vpc_id               = "vpc-0123456789abcdef0"
      }
      opa10 = {
        agent_tags = ["staging"]
        vpc_id     = "vpc-0fedcba9876543210"
      }
    }
  }

  assert {
    condition = one([
      for statement in jsondecode(aws_iam_policy.artifacts["opa1"].policy).Statement :
      statement.Resource if statement.Sid == "ArtifactsBucketObjectReadWrite"
    ]) == ["arn:aws:s3:::sb-data-artifacts-us-east-1-123456789012/team-a/6fdc0c6b96ee8a74/*"]
    error_message = "IAM must grant <keyPrefix>/<profileToken>/*, covering every kind."
  }

  assert {
    condition     = output.agents["opa1"].artifacts_key_prefix == "team-a"
    error_message = "The output wired into artifacts.keyPrefix must be only the optional namespace."
  }

  assert {
    condition     = output.agents["opa10"].artifacts_key_prefix == ""
    error_message = "An agent that names no prefix must leave artifacts.keyPrefix empty."
  }

  # printf '%s' staging | shasum -a 256 | cut -c1-16 => e919a75364398a44
  assert {
    condition = one([
      for statement in jsondecode(aws_iam_policy.artifacts["opa10"].policy).Statement :
      statement.Resource if statement.Sid == "ArtifactsBucketObjectReadWrite"
    ]) == ["arn:aws:s3:::sb-data-artifacts-us-east-1-123456789012/e919a75364398a44/*"]
    error_message = "A default-prefix agent must stay on <profileToken>/* and must not reach another agent's namespaced objects."
  }
}

run "wildcard_key_prefixes_are_rejected" {
  command = plan

  variables {
    agents = {
      opa1 = {
        agent_tags           = ["nonprod"]
        artifacts_key_prefix = "imports/*"
        vpc_id               = "vpc-0123456789abcdef0"
      }
    }
  }

  expect_failures = [var.agents]
}

run "nested_effective_artifact_prefixes_are_rejected" {
  command = plan

  variables {
    agents = {
      opa1 = {
        agent_tags = ["nonprod"]
        vpc_id     = "vpc-0123456789abcdef0"
      }
      opa10 = {
        agent_tags           = ["staging"]
        artifacts_key_prefix = "6fdc0c6b96ee8a74"
        vpc_id               = "vpc-0fedcba9876543210"
      }
    }
  }

  expect_failures = [var.agents]
}
