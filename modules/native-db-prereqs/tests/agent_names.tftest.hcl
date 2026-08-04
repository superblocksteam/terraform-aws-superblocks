# Agent names (the agents map keys) are embedded in IAM role names. Restrict
# them to lowercase alphanumeric so a later resource that rejects hyphens or
# underscores does not force a rename after databases exist.

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
  }
}

run "agent_names_reject_hyphens" {
  command = plan

  variables {
    agents = {
      "opa-1" = {
        agent_tags = ["nonprod"]
        vpc_id     = "vpc-0123456789abcdef0"
      }
    }
  }

  expect_failures = [var.agents]
}

run "agent_names_reject_underscores" {
  command = plan

  variables {
    agents = {
      "opa_1" = {
        agent_tags = ["nonprod"]
        vpc_id     = "vpc-0123456789abcdef0"
      }
    }
  }

  expect_failures = [var.agents]
}
