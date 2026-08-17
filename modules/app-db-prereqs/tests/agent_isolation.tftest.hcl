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
          jsondecode(aws_iam_policy.lifecycle_worker_observability[name].policy),
          ] : toset(one([
            for statement in policy.Statement :
            statement.Condition["ForAllValues:StringNotEquals"]["aws:TagKeys"]
            if try(statement.Condition["ForAllValues:StringNotEquals"]["aws:TagKeys"], null) != null
        ])) == toset(["AgentName", "ManagedBy", "Vpc", "aws-apn-id", "superblocks:owned"])
      ])
    ])
    error_message = "Workers must not be allowed to remove AgentName, the other IAM scoping tags, or the ownership pair from managed resources (including CloudWatch log groups)."
  }

  assert {
    condition = alltrue([
      for name in keys(var.agents) : alltrue([
        length([
          for statement in jsondecode(aws_iam_policy.lifecycle_worker_rds_mutation[name].policy).Statement : statement
          if try(statement.Sid, null) == "DenyRemoveProtectedTags" &&
          try(statement.Effect, null) == "Deny" &&
          try(statement.Action, null) == "rds:RemoveTagsFromResource" &&
          try(toset(statement.Condition["ForAnyValue:StringEquals"]["aws:TagKeys"]), null) == toset(["AgentName", "ManagedBy", "Vpc", "aws-apn-id", "superblocks:owned"])
        ]) == 1,
        length([
          for statement in jsondecode(aws_iam_policy.lifecycle_worker_ec2_provisioning[name].policy).Statement : statement
          if try(statement.Sid, null) == "DenyDeleteProtectedTags" &&
          try(statement.Effect, null) == "Deny" &&
          contains(try(tolist(statement.Action), [statement.Action]), "ec2:DeleteTags") &&
          try(statement.Condition.StringEquals["aws:ResourceTag/AgentName"], null) == name &&
          try(statement.Condition.StringEquals["aws:ResourceTag/ManagedBy"], null) == "superblocks-app-database-lifecycle" &&
          try(statement.Condition.StringEquals["aws:ResourceTag/Vpc"], null) == var.agents[name].vpc_id &&
          try(toset(statement.Condition["ForAnyValue:StringEquals"]["aws:TagKeys"]), null) == toset(["AgentName", "ManagedBy", "Vpc", "aws-apn-id", "superblocks:owned"])
        ]) == 1,
        length([
          for statement in jsondecode(aws_iam_policy.lifecycle_worker_observability[name].policy).Statement : statement
          if try(statement.Sid, null) == "DenyUntagProtectedTags" &&
          try(statement.Effect, null) == "Deny" &&
          try(statement.Action, null) == "logs:UntagResource" &&
          try(toset(statement.Condition["ForAnyValue:StringEquals"]["aws:TagKeys"]), null) == toset(["AgentName", "ManagedBy", "Vpc", "aws-apn-id", "superblocks:owned"])
        ]) == 1,
      ])
    ])
    error_message = "RDS, EC2, and CloudWatch mutation policies must Deny removing protected tag keys via named Sids; EC2 Deny must also require this agent's ResourceTag scope."
  }

  # AWS DeleteTags with no Tags parameter clears every user tag and omits
  # aws:TagKeys. ForAllValues:StringNotEquals then evaluates true (vacuous)
  # while ForAnyValue:StringEquals does not match — so protected-key Deny alone
  # is not enough. Require TagKeys to be present on the Allow, and Deny when it
  # is absent, both scoped to this agent's resources.
  assert {
    condition = alltrue([
      for name in keys(var.agents) : alltrue([
        try(one([
          for statement in jsondecode(aws_iam_policy.lifecycle_worker_ec2_provisioning[name].policy).Statement :
          statement.Condition.Null if try(statement.Sid, null) == "Ec2DeleteTagsExceptProtectedTags"
          ])["aws:TagKeys"], null) == "false",
        length([
          for statement in jsondecode(aws_iam_policy.lifecycle_worker_ec2_provisioning[name].policy).Statement : statement
          if try(statement.Sid, null) == "DenyDeleteTagsWhenTagKeysAbsent" &&
          try(statement.Effect, null) == "Deny" &&
          contains(try(tolist(statement.Action), [statement.Action]), "ec2:DeleteTags") &&
          try(statement.Condition.StringEquals["aws:ResourceTag/AgentName"], null) == name &&
          try(statement.Condition.StringEquals["aws:ResourceTag/ManagedBy"], null) == "superblocks-app-database-lifecycle" &&
          try(statement.Condition.StringEquals["aws:ResourceTag/Vpc"], null) == var.agents[name].vpc_id &&
          try(statement.Condition.Null["aws:TagKeys"], null) == "true"
        ]) == 1,
      ])
    ])
    error_message = "EC2 DeleteTags must Deny the delete-all request (missing aws:TagKeys) and the Allow must require TagKeys to be present."
  }

  # Every AddTags/CreateTags/TagResource Allow that can write ownership keys must
  # require the canonical values when those keys appear in the request. Checking
  # only one Sid leaves overlapping Allows that IAM ORs as a bypass.
  assert {
    condition = alltrue([
      for name in keys(var.agents) : alltrue(flatten([
        [
          for statement in concat(
            jsondecode(aws_iam_policy.lifecycle_worker_rds_provisioning[name].policy).Statement,
            jsondecode(aws_iam_policy.lifecycle_worker_rds_mutation[name].policy).Statement,
            ) : (
            try(statement.Condition.StringEqualsIfExists["aws:RequestTag/superblocks:owned"], null) == "true" &&
            try(statement.Condition.StringEqualsIfExists["aws:RequestTag/aws-apn-id"], null) == "pc:ctelqp437y3cvjkv5rv0z2w4f"
            ) if contains(try(tolist(statement.Action), [statement.Action]), "rds:AddTagsToResource")
        ],
        [
          for statement in jsondecode(aws_iam_policy.lifecycle_worker_ec2_provisioning[name].policy).Statement : (
            try(statement.Condition.StringEqualsIfExists["aws:RequestTag/superblocks:owned"], null) == "true" &&
            try(statement.Condition.StringEqualsIfExists["aws:RequestTag/aws-apn-id"], null) == "pc:ctelqp437y3cvjkv5rv0z2w4f"
            ) if contains(try(tolist(statement.Action), [statement.Action]), "ec2:CreateTags")
        ],
        [
          for statement in jsondecode(aws_iam_policy.lifecycle_worker_observability[name].policy).Statement : (
            try(statement.Condition.StringEqualsIfExists["aws:RequestTag/superblocks:owned"], null) == "true" &&
            try(statement.Condition.StringEqualsIfExists["aws:RequestTag/aws-apn-id"], null) == "pc:ctelqp437y3cvjkv5rv0z2w4f"
            ) if contains(try(tolist(statement.Action), [statement.Action]), "logs:TagResource")
        ],
      ]))
    ])
    error_message = "Every AddTags/CreateTags/TagResource Allow must require canonical ownership values via StringEqualsIfExists — overlapping Allows must not bypass the check."
  }

  assert {
    condition = alltrue([
      for name in keys(var.agents) : alltrue([
        for statement in jsondecode(aws_iam_policy.lifecycle_worker_ec2_provisioning[name].policy).Statement : (
          statement.Sid != "Ec2CreateTagsOnCreateSecurityGroup" ||
          (
            toset(try(tolist(statement.Resource), [statement.Resource])) == toset([
              "arn:aws:ec2:us-east-1:123456789012:security-group-rule/*",
              "arn:aws:ec2:us-east-1:123456789012:security-group/*",
            ]) &&
            toset(try(tolist(statement.Condition.StringEquals["ec2:CreateAction"]), [statement.Condition.StringEquals["ec2:CreateAction"]])) == toset([
              "AuthorizeSecurityGroupEgress",
              "AuthorizeSecurityGroupIngress",
              "CreateSecurityGroup",
            ])
          )
        )
      ])
    ])
    error_message = "Create-time EC2 tagging must authorize security-group and security-group-rule resources for CreateSecurityGroup plus AuthorizeSecurityGroupIngress/Egress."
  }

  assert {
    condition = alltrue([
      for name in keys(var.agents) : length([
        for statement in jsondecode(aws_iam_policy.lifecycle_worker_ec2_provisioning[name].policy).Statement : statement
        if try(statement.Sid, null) == "Ec2CreateTaggedSecurityGroupRules" &&
        try(statement.Effect, null) == "Allow" &&
        toset(try(tolist(statement.Action), [statement.Action])) == toset([
          "ec2:AuthorizeSecurityGroupEgress",
          "ec2:AuthorizeSecurityGroupIngress",
        ]) &&
        try(statement.Resource, null) == "arn:aws:ec2:us-east-1:123456789012:security-group-rule/*" &&
        try(statement.Condition.StringEquals["aws:RequestTag/AgentName"], null) == name &&
        try(statement.Condition.StringEquals["aws:RequestTag/ManagedBy"], null) == "superblocks-app-database-lifecycle" &&
        try(statement.Condition.StringEquals["aws:RequestTag/Vpc"], null) == var.agents[name].vpc_id &&
        try(statement.Condition.StringEqualsIfExists["aws:RequestTag/aws-apn-id"], null) == "pc:ctelqp437y3cvjkv5rv0z2w4f" &&
        try(statement.Condition.StringEqualsIfExists["aws:RequestTag/superblocks:owned"], null) == "true"
      ]) == 1
    ])
    error_message = "Security-group rule creates must authorize the new rule ARN from canonical request tags; resource tags do not exist yet."
  }
}
