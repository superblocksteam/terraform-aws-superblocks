# Accounts that require new roles to carry a named permissions boundary deny
# iam:CreateRole for any role created without it, so every role this module
# creates has to take the boundary at creation time.

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

  mock_resource "aws_s3_bucket" {
    defaults = {
      arn = "arn:aws:s3:::sb-data-artifacts-us-east-1-123456789012"
      id  = "sb-data-artifacts-us-east-1-123456789012"
    }
  }
}

variables {
  allowed_origins = ["https://app.superblocks.com"]
  deployment_type = "fargate"
  region          = "us-east-1"

  agents = {
    prod = {
      agent_tags = ["production"]
      vpc_id     = "vpc-0123456789abcdef0"
    }
  }
}

run "roles_have_no_boundary_by_default" {
  command = plan

  assert {
    condition     = aws_iam_role.lifecycle_worker["prod"].permissions_boundary == null
    error_message = "The lifecycle worker role must carry no permissions boundary unless permissions_boundary is set."
  }

  assert {
    condition     = aws_iam_role.connector["prod"].permissions_boundary == null
    error_message = "The connector role must carry no permissions boundary unless permissions_boundary is set."
  }

  assert {
    condition     = aws_iam_role.enhanced_monitoring[0].permissions_boundary == null
    error_message = "The Enhanced Monitoring role must carry no permissions boundary unless permissions_boundary is set."
  }
}

run "every_created_role_carries_the_boundary" {
  command = plan

  variables {
    permissions_boundary = "arn:aws:iam::123456789012:policy/example-boundary"
  }

  assert {
    condition     = aws_iam_role.lifecycle_worker["prod"].permissions_boundary == "arn:aws:iam::123456789012:policy/example-boundary"
    error_message = "The lifecycle worker role must carry permissions_boundary when it is set."
  }

  assert {
    condition     = aws_iam_role.connector["prod"].permissions_boundary == "arn:aws:iam::123456789012:policy/example-boundary"
    error_message = "The connector role must carry permissions_boundary when it is set."
  }

  assert {
    condition     = aws_iam_role.enhanced_monitoring[0].permissions_boundary == "arn:aws:iam::123456789012:policy/example-boundary"
    error_message = "The Enhanced Monitoring role must carry permissions_boundary when it is set."
  }
}

run "aws_managed_boundary_is_accepted" {
  command = plan

  variables {
    permissions_boundary = "arn:aws:iam::aws:policy/PowerUserAccess"
  }

  assert {
    condition     = aws_iam_role.connector["prod"].permissions_boundary == "arn:aws:iam::aws:policy/PowerUserAccess"
    error_message = "An AWS managed policy ARN must be accepted as a boundary."
  }
}

run "bare_policy_name_is_rejected" {
  command = plan

  variables {
    permissions_boundary = "example-boundary"
  }

  expect_failures = [
    var.permissions_boundary,
  ]
}

# A boundary is always a managed policy, never a role.
run "role_arn_is_rejected" {
  command = plan

  variables {
    permissions_boundary = "arn:aws:iam::123456789012:role/example-boundary"
  }

  expect_failures = [
    var.permissions_boundary,
  ]
}
