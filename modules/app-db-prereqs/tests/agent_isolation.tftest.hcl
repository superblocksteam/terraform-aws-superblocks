# Every lifecycle worker in a shared account and VPC sees the same sb-* RDS
# ARN namespace. AgentName is therefore the final authorization boundary:
# matching ManagedBy and Vpc tags alone must never authorize another OPA's
# resources.

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
      agent_tags = ["production"]
      vpc_id     = "vpc-0123456789abcdef0"
    }
    opa2 = {
      agent_tags = ["staging"]
      vpc_id     = "vpc-0123456789abcdef0"
    }
  }
}

run "lifecycle_policies_require_matching_agent_name" {
  command = plan

  assert {
    condition = alltrue([
      for name in keys(var.agents) : alltrue([
        for statement in jsondecode(aws_iam_policy.lifecycle_worker_rds_mutation[name].policy).Statement :
        try(statement.Condition.StringEquals["aws:ResourceTag/ManagedBy"], null) == null ||
        try(statement.Condition.StringEquals["aws:ResourceTag/AgentName"], null) == name
      ])
    ])
    error_message = "Every RDS mutation scoped by ManagedBy must also require the lifecycle worker's own AgentName."
  }

  assert {
    condition = alltrue([
      for name in keys(var.agents) : alltrue([
        for statement in concat(
          jsondecode(aws_iam_policy.lifecycle_worker_rds_provisioning[name].policy).Statement,
          jsondecode(aws_iam_policy.lifecycle_worker_rds_mutation[name].policy).Statement,
        ) :
        (
          try(statement.Condition.StringEquals["aws:RequestTag/ManagedBy"], null) == null ||
          try(statement.Condition.StringEquals["aws:RequestTag/AgentName"], null) == name
          ) && (
          try(statement.Condition.StringEqualsIfExists["aws:RequestTag/ManagedBy"], null) == null ||
          try(statement.Condition.StringEqualsIfExists["aws:RequestTag/AgentName"], null) == name
        )
      ])
    ])
    error_message = "Every RDS create or tag request scoped by ManagedBy must also require the lifecycle worker's own AgentName."
  }

  assert {
    condition = alltrue([
      for name in keys(var.agents) : alltrue([
        for statement in jsondecode(aws_iam_policy.lifecycle_worker_ec2_provisioning[name].policy).Statement :
        (
          try(statement.Condition.StringEquals["aws:RequestTag/ManagedBy"], null) == null ||
          try(statement.Condition.StringEquals["aws:RequestTag/AgentName"], null) == name
          ) && (
          try(statement.Condition.StringEquals["aws:ResourceTag/ManagedBy"], null) == null ||
          try(statement.Condition.StringEquals["aws:ResourceTag/AgentName"], null) == name
          ) && (
          try(statement.Condition.StringEqualsIfExists["aws:RequestTag/ManagedBy"], null) == null ||
          try(statement.Condition.StringEqualsIfExists["aws:RequestTag/AgentName"], null) == name
        )
      ])
    ])
    error_message = "Every EC2 security-group action scoped by ManagedBy must also require the lifecycle worker's own AgentName."
  }

  assert {
    condition = alltrue([
      for name in keys(var.agents) : alltrue([
        for statement in jsondecode(aws_iam_policy.lifecycle_worker_secrets[name].policy).Statement :
        (
          try(statement.Condition.StringEquals["aws:RequestTag/ManagedBy"], null) == null ||
          try(statement.Condition.StringEquals["aws:RequestTag/AgentName"], null) == name
          ) && (
          try(statement.Condition.StringEquals["aws:ResourceTag/ManagedBy"], null) == null ||
          try(statement.Condition.StringEquals["aws:ResourceTag/AgentName"], null) == name
        )
      ])
    ])
    error_message = "Every RDS-managed secret action scoped by ManagedBy must also require the lifecycle worker's own AgentName."
  }

  assert {
    condition = alltrue([
      for name in keys(var.agents) : alltrue([
        for policy in [
          jsondecode(aws_iam_policy.lifecycle_worker_ec2_provisioning[name].policy),
          jsondecode(aws_iam_policy.lifecycle_worker_rds_mutation[name].policy),
          ] : toset(one([
            for statement in policy.Statement :
            statement.Condition["ForAllValues:StringNotEquals"]["aws:TagKeys"]
            if try(statement.Condition["ForAllValues:StringNotEquals"]["aws:TagKeys"], null) != null
        ])) == toset(["AgentName", "ManagedBy", "Vpc"])
      ])
    ])
    error_message = "Workers must not be allowed to remove AgentName or the other IAM scoping tags from managed resources."
  }
}
