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
      arn = "arn:aws:s3:::sb-app-db-us-east-1-123456789012"
      id  = "sb-app-db-us-east-1-123456789012"
    }
  }
}

run "ec2_vpc_describe_grants_required_reads" {
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

  # Pins the full Ec2VpcDescribe allowlist. DescribeRouteTables is easy to drop
  # in a "remove unused IAM" cleanup — nothing in this module calls it — but
  # reading data.aws_vpc in the physical modules resolves the VPC's main route
  # table, and without the grant every plan/apply logs AccessDenied.
  assert {
    condition = toset(one([
      for statement in jsondecode(aws_iam_policy.lifecycle_worker_ec2_provisioning["opa1"].policy).Statement :
      statement.Action if statement.Sid == "Ec2VpcDescribe"
    ])) == toset([
      "ec2:DescribeAccountAttributes",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeRouteTables",
      "ec2:DescribeSecurityGroupRules",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSubnets",
      "ec2:DescribeTags",
      "ec2:DescribeVpcAttribute",
      "ec2:DescribeVpcs",
    ])
    error_message = "Ec2VpcDescribe must grant every EC2 describe the physical modules (and data.aws_vpc) perform."
  }
}
