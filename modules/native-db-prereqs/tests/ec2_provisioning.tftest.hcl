mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
      arn        = "arn:aws:iam::123456789012:root"
      user_id    = "AIDAEXAMPLE"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/mock-role"
      id  = "mock-role"
    }
  }

  mock_resource "aws_iam_policy" {
    defaults = {
      arn = "arn:aws:iam::123456789012:policy/mock-policy"
      id  = "arn:aws:iam::123456789012:policy/mock-policy"
    }
  }

  mock_resource "aws_s3_bucket" {
    defaults = {
      arn = "arn:aws:s3:::sb-native-db-us-east-1-123456789012"
      id  = "sb-native-db-us-east-1-123456789012"
    }
  }
}

run "grants_the_reads_the_physical_modules_perform" {
  command = plan

  variables {
    deployment_type = "eks"
    region          = "us-east-1"
    agents = {
      opa1 = {
        agent_tags        = ["nonprod"]
        vpc_id            = "vpc-0123456789abcdef0"
        oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE1234567890"
      }
    }
  }

  # The physical modules declare data.aws_vpc, and reading it resolves the VPC's
  # main route table. Without this grant the read still succeeds, so provisioning
  # works, but every plan and apply logs an AccessDenied in the customer account.
  assert {
    condition = contains(one([
      for statement in jsondecode(aws_iam_policy.lifecycle_worker_ec2_provisioning["opa1"].policy).Statement :
      statement.Action if statement.Sid == "Ec2VpcDescribe"
    ]), "ec2:DescribeRouteTables")
    error_message = "Reading data.aws_vpc calls ec2:DescribeRouteTables, so the worker must be granted it."
  }
}
