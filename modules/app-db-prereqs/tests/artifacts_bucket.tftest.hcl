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

  mock_data "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/existing-worker"
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
  allowed_origins         = ["https://app.superblocks.com"]
  create_artifacts_bucket = true
  deployment_type         = "fargate"
  region                  = "us-east-1"

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
    condition     = aws_s3_bucket.artifacts[0].bucket == "sb-data-artifacts-us-east-1-123456789012"
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
    condition     = aws_s3_bucket.artifacts[0].bucket == "acme-data-artifacts-us-east-1-123456789012"
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
    error_message = "A non-empty allowed_origins list must replace the data-domain origin."
  }
}

run "incomplete_multipart_uploads_abort_after_seven_days" {
  command = plan

  assert {
    condition     = one(aws_s3_bucket_lifecycle_configuration.artifacts[0].rule).abort_incomplete_multipart_upload[0].days_after_initiation == 7
    error_message = "Incomplete multipart uploads must be aborted after seven days."
  }

  assert {
    condition     = length(one(aws_s3_bucket_lifecycle_configuration.artifacts[0].rule).expiration) == 0
    error_message = "The multipart safety net must not expire completed artifacts."
  }
}

run "public_access_is_blocked" {
  command = plan

  assert {
    condition = (
      aws_s3_bucket_public_access_block.artifacts[0].block_public_acls &&
      aws_s3_bucket_public_access_block.artifacts[0].block_public_policy &&
      aws_s3_bucket_public_access_block.artifacts[0].ignore_public_acls &&
      aws_s3_bucket_public_access_block.artifacts[0].restrict_public_buckets
    )
    error_message = "The artifacts bucket must block all public access, matching the state bucket."
  }

  assert {
    condition = (
      one([
        for statement in jsondecode(aws_s3_bucket_policy.artifacts[0].policy).Statement :
        statement if statement.Sid == "DenyInsecureTransport"
      ]).Effect == "Deny" &&
      one([
        for statement in jsondecode(aws_s3_bucket_policy.artifacts[0].policy).Statement :
        statement if statement.Sid == "DenyInsecureTransport"
      ]).Condition.Bool["aws:SecureTransport"] == "false" &&
      toset(flatten([
        one([
          for statement in jsondecode(aws_s3_bucket_policy.artifacts[0].policy).Statement :
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
    condition     = aws_iam_role_policy_attachment.lifecycle_worker_artifacts["opa1"].role == aws_iam_role.lifecycle_worker["opa1"].name
    error_message = "The dedicated artifacts policy must be attached to the lifecycle worker."
  }

  assert {
    condition = !contains([
      for statement in jsondecode(aws_iam_policy.artifacts["opa1"].policy).Statement :
      try(statement.Sid, "")
    ], "ArtifactsBucketKms")
    error_message = "Without artifacts_kms_key_arn the policy must not grant KMS permissions."
  }

  assert {
    condition = (
      output.artifacts_server_side_encryption_algorithm == "AES256" &&
      output.artifacts_kms_key_arn == null &&
      !contains([
        for statement in jsondecode(aws_s3_bucket_policy.artifacts[0].policy).Statement :
        try(statement.Sid, "")
      ], "DenyIncorrectEncryptionAlgorithm") &&
      !contains([
        for statement in jsondecode(aws_s3_bucket_policy.artifacts[0].policy).Statement :
        try(statement.Sid, "")
      ], "DenyIncorrectEncryptionKey")
    )
    error_message = "Without artifacts_kms_key_arn the bucket must use SSE-S3 and must not deny encryption headers."
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

  assert {
    condition = one([
      for r in one(aws_s3_bucket_server_side_encryption_configuration.artifacts).rule :
      one(r.apply_server_side_encryption_by_default).sse_algorithm
    ]) == "aws:kms"
    error_message = "artifacts_kms_key_arn must select SSE-KMS."
  }

  assert {
    condition = toset(one([
      for r in one(aws_s3_bucket_server_side_encryption_configuration.artifacts).rule :
      r.blocked_encryption_types
    ])) == toset(["SSE-C"])
    error_message = "SSE-KMS on artifacts must still block SSE-C."
  }

  assert {
    condition = (
      output.artifacts_server_side_encryption_algorithm == "aws:kms" &&
      output.artifacts_kms_key_arn == "arn:aws:kms:us-east-1:123456789012:key/mrk-artifacts" &&
      one([
        for statement in jsondecode(aws_s3_bucket_policy.artifacts[0].policy).Statement :
        statement.Condition.Null["s3:x-amz-server-side-encryption"]
        if statement.Sid == "DenyIncorrectEncryptionAlgorithm"
      ]) == "false" &&
      one([
        for statement in jsondecode(aws_s3_bucket_policy.artifacts[0].policy).Statement :
        statement.Condition.StringNotEquals["s3:x-amz-server-side-encryption"]
        if statement.Sid == "DenyIncorrectEncryptionAlgorithm"
      ]) == "aws:kms" &&
      one([
        for statement in jsondecode(aws_s3_bucket_policy.artifacts[0].policy).Statement :
        statement.Condition.Null["s3:x-amz-server-side-encryption-aws-kms-key-id"]
        if statement.Sid == "DenyIncorrectEncryptionKey"
      ]) == "false" &&
      one([
        for statement in jsondecode(aws_s3_bucket_policy.artifacts[0].policy).Statement :
        statement.Condition.StringNotEquals["s3:x-amz-server-side-encryption-aws-kms-key-id"]
        if statement.Sid == "DenyIncorrectEncryptionKey"
      ]) == "arn:aws:kms:us-east-1:123456789012:key/mrk-artifacts"
    )
    error_message = "A KMS key must deny PutObject whose encryption headers name a different algorithm or key."
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
    condition = one([
      for r in one(aws_s3_bucket_server_side_encryption_configuration.artifacts).rule :
      one(r.apply_server_side_encryption_by_default).sse_algorithm
    ]) == "AES256"
    error_message = "Without artifacts_kms_key_arn the artifacts bucket must use SSE-S3."
  }

  assert {
    condition = toset(one([
      for r in one(aws_s3_bucket_server_side_encryption_configuration.artifacts).rule :
      r.blocked_encryption_types
    ])) == toset(["SSE-C"])
    error_message = "SSE-S3 on artifacts must block SSE-C."
  }

  assert {
    condition = one([
      for r in one(aws_s3_bucket_server_side_encryption_configuration.artifacts).rule :
      r.bucket_key_enabled
    ]) == false
    error_message = "SSE-S3 on artifacts must not enable a bucket key."
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

run "cors_defaults_to_the_data_domain" {
  command = plan

  variables {
    allowed_origins = []
  }

  assert {
    condition     = one(aws_s3_bucket_cors_configuration.artifacts[0].cors_rule).allowed_origins == toset(["https://app.superblocks.com"])
    error_message = "An empty allowed_origins list must allow the default data domain."
  }
}

run "cors_follows_the_eu_data_domain" {
  command = plan

  variables {
    allowed_origins               = []
    superblocks_agent_data_domain = "eu.superblocks.com"
  }

  assert {
    condition     = one(aws_s3_bucket_cors_configuration.artifacts[0].cors_rule).allowed_origins == toset(["https://eu.superblocks.com"])
    error_message = "An empty allowed_origins list must allow https://<superblocks_agent_data_domain>."
  }
}

run "an_explicit_origin_replaces_the_data_domain" {
  command = plan

  variables {
    allowed_origins               = ["https://ui.example.com"]
    superblocks_agent_data_domain = "eu.superblocks.com"
  }

  assert {
    condition     = one(aws_s3_bucket_cors_configuration.artifacts[0].cors_rule).allowed_origins == toset(["https://ui.example.com"])
    error_message = "allowed_origins must replace the data-domain origin."
  }
}

run "an_unknown_data_domain_is_rejected" {
  command = plan

  variables {
    superblocks_agent_data_domain = "example.com"
  }

  expect_failures = [var.superblocks_agent_data_domain]
}

run "the_artifacts_bucket_is_omitted_by_default" {
  command = plan

  variables {
    create_artifacts_bucket = false
  }

  assert {
    condition     = length(aws_s3_bucket.artifacts) == 0
    error_message = "The artifacts bucket must be absent unless create_artifacts_bucket is true."
  }

  assert {
    condition     = output.artifacts_bucket_name == null
    error_message = "artifacts_bucket_name must be null when the bucket is not created."
  }

  assert {
    condition = (
      output.artifacts_kms_key_arn == null &&
      output.artifacts_server_side_encryption_algorithm == null
    )
    error_message = "Encryption outputs must be null when the artifacts bucket is not created."
  }

  assert {
    condition = (
      length(aws_iam_policy.artifacts) == 0 &&
      length(aws_iam_role_policy_attachment.lifecycle_worker_artifacts) == 0 &&
      length(aws_s3_bucket_public_access_block.artifacts) == 0 &&
      length(aws_s3_bucket_policy.artifacts) == 0 &&
      length(aws_s3_bucket_server_side_encryption_configuration.artifacts) == 0 &&
      length(aws_s3_bucket_cors_configuration.artifacts) == 0 &&
      length(aws_s3_bucket_lifecycle_configuration.artifacts) == 0
    )
    error_message = "Omitting the artifacts bucket must omit its dependents and the worker policy."
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.tofu_state[0].block_public_acls
    error_message = "Omitting the artifacts bucket must leave the state bucket public access block in place."
  }
}

run "the_artifacts_public_access_block_can_be_omitted" {
  command = plan

  variables {
    enable_public_access_blocks = false
  }

  assert {
    condition = (
      length(aws_s3_bucket_public_access_block.artifacts) == 0 &&
      length(aws_s3_bucket_public_access_block.tofu_state) == 0
    )
    error_message = "enable_public_access_blocks = false must omit both public access blocks."
  }

  assert {
    condition = (
      length(aws_s3_bucket.artifacts) == 1 &&
      length(aws_s3_bucket_policy.artifacts) == 1 &&
      aws_s3_bucket.tofu_state.bucket == "sb-app-db-us-east-1-123456789012"
    )
    error_message = "Omitting the public access blocks must keep both buckets and the artifacts HTTPS policy."
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

run "object_access_is_denied_except_for_lifecycle_workers" {
  command = plan

  assert {
    condition = (
      toset(flatten([
        one([
          for statement in jsondecode(aws_s3_bucket_policy.artifacts[0].policy).Statement :
          statement.Action if statement.Sid == "DenyObjectAccessExceptLifecycleWorkers"
        ])
        ])) == toset([
        "s3:AbortMultipartUpload",
        "s3:DeleteObject",
        "s3:GetObject",
        "s3:ListMultipartUploadParts",
        "s3:PutObject",
      ]) &&
      one([
        for statement in jsondecode(aws_s3_bucket_policy.artifacts[0].policy).Statement :
        statement.Resource if statement.Sid == "DenyObjectAccessExceptLifecycleWorkers"
      ]) == "arn:aws:s3:::sb-data-artifacts-us-east-1-123456789012/*" &&
      toset(flatten([
        one([
          for statement in jsondecode(aws_s3_bucket_policy.artifacts[0].policy).Statement :
          statement.Condition.ArnNotEquals["aws:PrincipalArn"]
          if statement.Sid == "DenyObjectAccessExceptLifecycleWorkers"
        ])
      ])) == toset(["arn:aws:iam::123456789012:role/mock"])
    )
    error_message = "Object actions must be denied unless the caller is a lifecycle worker role."
  }

  assert {
    condition = one([
      for statement in jsondecode(aws_s3_bucket_policy.artifacts[0].policy).Statement :
      statement.Condition.StringNotEquals["s3:signatureversion"]
      if statement.Sid == "DenySignatureVersionOtherThanSigV4"
    ]) == "AWS4-HMAC-SHA256"
    error_message = "The artifacts bucket must deny requests that are not Signature Version 4."
  }

  assert {
    condition = !contains([
      for statement in jsondecode(aws_s3_bucket_policy.artifacts[0].policy).Statement :
      try(statement.Sid, "")
    ], "DenyObjectAccessOutsideVpce")
    error_message = "The artifacts bucket policy must not deny object access based on a VPC endpoint."
  }
}

run "an_existing_role_and_an_exempt_principal_may_access_objects" {
  command = plan

  variables {
    artifacts_object_access_exempt_principal_arns = [
      "arn:aws:iam::123456789012:role/break-glass",
    ]
    agents = {
      opa1 = {
        agent_tags         = ["nonprod"]
        existing_role_name = "existing-worker"
        vpc_id             = "vpc-0123456789abcdef0"
      }
    }
  }

  assert {
    condition = toset(flatten([
      one([
        for statement in jsondecode(aws_s3_bucket_policy.artifacts[0].policy).Statement :
        statement.Condition.ArnNotEquals["aws:PrincipalArn"]
        if statement.Sid == "DenyObjectAccessExceptLifecycleWorkers"
      ])
      ])) == toset([
      "arn:aws:iam::123456789012:role/break-glass",
      "arn:aws:iam::123456789012:role/existing-worker",
    ])
    error_message = "The object-access deny must exempt the existing lifecycle role and the caller-supplied ARN."
  }
}

run "object_access_deny_can_be_disabled" {
  command = plan

  variables {
    restrict_artifacts_object_access = false
  }

  assert {
    condition = (
      !contains([
        for statement in jsondecode(aws_s3_bucket_policy.artifacts[0].policy).Statement :
        try(statement.Sid, "")
      ], "DenyObjectAccessExceptLifecycleWorkers") &&
      contains([
        for statement in jsondecode(aws_s3_bucket_policy.artifacts[0].policy).Statement :
        try(statement.Sid, "")
      ], "DenyInsecureTransport") &&
      contains([
        for statement in jsondecode(aws_s3_bucket_policy.artifacts[0].policy).Statement :
        try(statement.Sid, "")
      ], "DenySignatureVersionOtherThanSigV4")
    )
    error_message = "restrict_artifacts_object_access = false must drop only the object-access deny."
  }
}

run "wildcard_exempt_principals_are_rejected" {
  command = plan

  variables {
    artifacts_object_access_exempt_principal_arns = ["arn:aws:iam::123456789012:role/*"]
  }

  expect_failures = [var.artifacts_object_access_exempt_principal_arns]
}
