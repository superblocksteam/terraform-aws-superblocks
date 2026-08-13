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

# The mock defaults above give every aws_iam_policy the same arn, which would
# let a cross-resource assertion (attachment.policy_arn == policy.arn) pass
# even if the attachment referenced an adjacent policy by mistake. Overriding
# each address with its own arn makes those assertions load-bearing.
override_resource {
  target = aws_iam_role.lifecycle_worker
  values = { arn = "arn:aws:iam::123456789012:role/mock-lifecycle-worker" }
}

override_resource {
  target = aws_iam_role.connector
  values = { arn = "arn:aws:iam::123456789012:role/mock-connector" }
}

override_resource {
  target = aws_iam_role.enhanced_monitoring
  values = { arn = "arn:aws:iam::123456789012:role/mock-enhanced-monitoring" }
}

override_resource {
  target = aws_iam_policy.lifecycle_worker_observability
  values = { arn = "arn:aws:iam::123456789012:policy/mock-observability" }
}

override_resource {
  target = aws_iam_policy.lifecycle_worker_secrets
  values = { arn = "arn:aws:iam::123456789012:policy/mock-secrets" }
}

override_resource {
  target = aws_iam_policy.lifecycle_worker_assume_connector
  values = { arn = "arn:aws:iam::123456789012:policy/mock-assume-connector" }
}

override_resource {
  target = aws_iam_policy.lifecycle_worker_state_bucket
  values = { arn = "arn:aws:iam::123456789012:policy/mock-state-bucket" }
}

override_resource {
  target = aws_iam_policy.lifecycle_worker_rds_provisioning
  values = { arn = "arn:aws:iam::123456789012:policy/mock-rds-provisioning" }
}

override_resource {
  target = aws_iam_policy.lifecycle_worker_rds_mutation
  values = { arn = "arn:aws:iam::123456789012:policy/mock-rds-mutation" }
}

override_resource {
  target = aws_iam_policy.lifecycle_worker_ec2_provisioning
  values = { arn = "arn:aws:iam::123456789012:policy/mock-ec2-provisioning" }
}

override_resource {
  target = aws_iam_policy.connector
  values = { arn = "arn:aws:iam::123456789012:policy/mock-connector-policy" }
}

run "grants_app_database_observability_permissions" {
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

  assert {
    condition = alltrue([
      for action in [
        "logs:CreateLogGroup",
        "logs:DeleteLogGroup",
        "logs:ListTagsForResource",
        "logs:PutRetentionPolicy",
      ] :
      contains(one([
        for statement in jsondecode(aws_iam_policy.lifecycle_worker_observability["opa1"].policy).Statement :
        statement.Action if statement.Sid == "CloudWatchLogGroupsForAppDatabases"
      ]), action)
    ])
    error_message = "The worker must be able to manage the log groups the physical modules declare explicitly."
  }

  assert {
    condition = !contains(one([
      for statement in jsondecode(aws_iam_policy.lifecycle_worker_observability["opa1"].policy).Statement :
      try(tolist(statement.Action), [statement.Action]) if statement.Sid == "CloudWatchLogGroupsForAppDatabases"
    ]), "logs:UntagResource")
    error_message = "UntagResource must not sit in the unconditional CloudWatch allow — protected keys need Allow-with-exclusion plus Deny."
  }

  assert {
    condition = !contains(one([
      for statement in jsondecode(aws_iam_policy.lifecycle_worker_observability["opa1"].policy).Statement :
      try(tolist(statement.Action), [statement.Action]) if statement.Sid == "CloudWatchLogGroupsForAppDatabases"
    ]), "logs:TagResource")
    error_message = "TagResource must not sit in the unconditional CloudWatch allow — ownership request-tag values need StringEqualsIfExists."
  }

  assert {
    condition = (
      one([
        for statement in jsondecode(aws_iam_policy.lifecycle_worker_observability["opa1"].policy).Statement :
        statement.Action if statement.Sid == "CloudWatchTagResourceWithCanonicalOwnership"
      ]) == "logs:TagResource" &&
      try(one([
        for statement in jsondecode(aws_iam_policy.lifecycle_worker_observability["opa1"].policy).Statement :
        statement.Condition.StringEqualsIfExists if statement.Sid == "CloudWatchTagResourceWithCanonicalOwnership"
        ])["aws:RequestTag/superblocks:owned"], null) == "true" &&
      try(one([
        for statement in jsondecode(aws_iam_policy.lifecycle_worker_observability["opa1"].policy).Statement :
        statement.Condition.StringEqualsIfExists if statement.Sid == "CloudWatchTagResourceWithCanonicalOwnership"
        ])["aws:RequestTag/aws-apn-id"], null) == "pc:ctelqp437y3cvjkv5rv0z2w4f"
    )
    error_message = "CloudWatch TagResource Allow must require canonical ownership values via StringEqualsIfExists."
  }

  assert {
    condition = (
      one([
        for statement in jsondecode(aws_iam_policy.lifecycle_worker_observability["opa1"].policy).Statement :
        statement.Action if statement.Sid == "CloudWatchUntagExceptProtectedTags"
      ]) == "logs:UntagResource" &&
      toset(one([
        for statement in jsondecode(aws_iam_policy.lifecycle_worker_observability["opa1"].policy).Statement :
        statement.Condition["ForAllValues:StringNotEquals"]["aws:TagKeys"] if statement.Sid == "CloudWatchUntagExceptProtectedTags"
      ])) == toset(["AgentName", "ManagedBy", "Vpc", "aws-apn-id", "superblocks:owned"])
    )
    error_message = "CloudWatch UntagResource Allow must exclude the protected tag keys."
  }

  assert {
    condition = (
      one([
        for statement in jsondecode(aws_iam_policy.lifecycle_worker_observability["opa1"].policy).Statement :
        statement.Effect if statement.Sid == "DenyUntagProtectedTags"
      ]) == "Deny" &&
      one([
        for statement in jsondecode(aws_iam_policy.lifecycle_worker_observability["opa1"].policy).Statement :
        statement.Action if statement.Sid == "DenyUntagProtectedTags"
      ]) == "logs:UntagResource" &&
      toset(one([
        for statement in jsondecode(aws_iam_policy.lifecycle_worker_observability["opa1"].policy).Statement :
        statement.Condition["ForAnyValue:StringEquals"]["aws:TagKeys"] if statement.Sid == "DenyUntagProtectedTags"
      ])) == toset(["AgentName", "ManagedBy", "Vpc", "aws-apn-id", "superblocks:owned"])
    )
    error_message = "CloudWatch must Deny untagging protected keys via DenyUntagProtectedTags."
  }

  assert {
    condition = jsonencode(one([
      for statement in jsondecode(aws_iam_policy.lifecycle_worker_observability["opa1"].policy).Statement :
      statement.Resource if statement.Sid == "CloudWatchLogGroupsForAppDatabases"
      ])) == jsonencode([
      "arn:aws:logs:us-east-1:123456789012:log-group:/aws/rds/cluster/sb-*",
      "arn:aws:logs:us-east-1:123456789012:log-group:/aws/rds/instance/sb-*",
    ])
    error_message = "CloudWatch Logs grants must stay inside the sb-* namespace the physical modules generate."
  }

  # Verified with aws iam simulate-custom-policy: DescribeLogGroups evaluates to
  # implicitDeny against a log-group ARN no matter how the pattern is written,
  # and to allowed only against "*". Every other action here is resource
  # scopable, so keeping them in one statement would silently widen them.
  assert {
    condition = !contains(one([
      for statement in jsondecode(aws_iam_policy.lifecycle_worker_observability["opa1"].policy).Statement :
      statement.Action if statement.Sid == "CloudWatchLogGroupsForAppDatabases"
    ]), "logs:DescribeLogGroups")
    error_message = "DescribeLogGroups cannot sit in the sb-* scoped statement: AWS will not authorize it against a log-group ARN, so the provider's read fails with AccessDenied."
  }

  assert {
    condition = (
      one([
        for statement in jsondecode(aws_iam_policy.lifecycle_worker_observability["opa1"].policy).Statement :
        statement.Action if statement.Sid == "DescribeLogGroupsIsNotResourceScopable"
      ]) == "logs:DescribeLogGroups" &&
      one([
        for statement in jsondecode(aws_iam_policy.lifecycle_worker_observability["opa1"].policy).Statement :
        statement.Resource if statement.Sid == "DescribeLogGroupsIsNotResourceScopable"
      ]) == "*"
    )
    error_message = "The provider reads aws_cloudwatch_log_group through DescribeLogGroups, which only authorizes against \"*\"."
  }

  assert {
    condition = (
      one([
        for statement in jsondecode(aws_iam_policy.lifecycle_worker_observability["opa1"].policy).Statement :
        statement.Action if statement.Sid == "PassEnhancedMonitoringRole"
      ]) == "iam:PassRole" &&
      one([
        for statement in jsondecode(aws_iam_policy.lifecycle_worker_observability["opa1"].policy).Statement :
        statement.Resource if statement.Sid == "PassEnhancedMonitoringRole"
      ]) == local.monitoring_role_arn &&
      one([
        for statement in jsondecode(aws_iam_policy.lifecycle_worker_observability["opa1"].policy).Statement :
        statement.Condition.StringEquals["iam:PassedToService"] if statement.Sid == "PassEnhancedMonitoringRole"
      ]) == "rds.amazonaws.com"
    )
    error_message = "Enhanced Monitoring attach requires iam:PassRole scoped to the shared monitoring role, conditioned on the service RDS actually passes it as (rds.amazonaws.com, not the monitoring.rds.amazonaws.com principal that assumes it)."
  }

  assert {
    condition = (
      aws_iam_role.enhanced_monitoring[0].name == "sb-app-db-enhanced-monitoring" &&
      jsondecode(aws_iam_role.enhanced_monitoring[0].assume_role_policy).Statement[0].Principal.Service == "monitoring.rds.amazonaws.com" &&
      jsondecode(aws_iam_role.enhanced_monitoring[0].assume_role_policy).Statement[0].Action == "sts:AssumeRole" &&
      jsonencode(jsondecode(aws_iam_role.enhanced_monitoring[0].assume_role_policy).Statement[0].Condition.ArnLike["aws:SourceArn"]) == jsonencode([
        "arn:aws:rds:*:123456789012:cluster:sb-*",
        "arn:aws:rds:*:123456789012:db:sb-*",
      ]) &&
      jsondecode(aws_iam_role.enhanced_monitoring[0].assume_role_policy).Statement[0].Condition.StringEquals["aws:SourceAccount"] == "123456789012"
    )
    error_message = "The shared monitoring role must trust RDS monitoring for sb-* databases in this account only, across every region it provisions into."
  }

  assert {
    condition     = aws_iam_role_policy_attachment.enhanced_monitoring[0].policy_arn == "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
    error_message = "The monitoring role must carry the AWS-managed Enhanced Monitoring policy rather than a hand-written copy."
  }

  assert {
    condition = (
      aws_iam_role_policy_attachment.lifecycle_worker_observability["opa1"].role == local.agent_role_names["opa1"] &&
      aws_iam_role_policy_attachment.lifecycle_worker_observability["opa1"].policy_arn == aws_iam_policy.lifecycle_worker_observability["opa1"].arn
    )
    error_message = "The observability policy must be attached to the lifecycle worker role, not merely declared."
  }

  assert {
    condition     = output.enhanced_monitoring_role_arn == local.monitoring_role_arn
    error_message = "The monitoring role ARN must be exported so operators can pass it as monitoring_role_arn to the physical modules."
  }
}

run "reuses_an_existing_monitoring_role" {
  command = plan

  variables {
    deployment_type              = "eks"
    region                       = "us-west-2"
    existing_monitoring_role_arn = "arn:aws:iam::123456789012:role/platform/sb-app-db-enhanced-monitoring"
    agents = {
      opa1 = {
        agent_tags        = ["staging"]
        vpc_id            = "vpc-0fedcba9876543210"
        oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-west-2.amazonaws.com/id/EXAMPLE0987654321"
      }
    }
  }

  assert {
    condition     = length(aws_iam_role.enhanced_monitoring) == 0
    error_message = "When existing_monitoring_role_arn is set, the module must not create a second monitoring role."
  }

  assert {
    condition = one([
      for statement in jsondecode(aws_iam_policy.lifecycle_worker_observability["opa1"].policy).Statement :
      statement.Resource if statement.Sid == "PassEnhancedMonitoringRole"
    ]) == "arn:aws:iam::123456789012:role/platform/sb-app-db-enhanced-monitoring"
    error_message = "A worker that reuses an existing monitoring role must be able to pass that role."
  }

  assert {
    condition     = output.enhanced_monitoring_role_arn == "arn:aws:iam::123456789012:role/platform/sb-app-db-enhanced-monitoring"
    error_message = "The monitoring role output must expose the existing role when one is supplied."
  }
}

# Every ARN this module builds hardcodes the aws partition, including the
# AmazonRDSEnhancedMonitoringRole managed-policy ARN and the RDS SourceArn
# patterns in the trust policy. A GovCloud role would pass an ARN-shape check
# but never actually be assumable by monitoring.rds.amazonaws.com here, so the
# validation has to reject it at plan time rather than at provision time.
run "rejects_a_monitoring_role_outside_the_aws_partition" {
  command = plan

  variables {
    deployment_type              = "eks"
    region                       = "us-gov-west-1"
    existing_monitoring_role_arn = "arn:aws-us-gov:iam::123456789012:role/sb-app-db-enhanced-monitoring"
    agents = {
      opa1 = {
        agent_tags        = ["nonprod"]
        vpc_id            = "vpc-0123456789abcdef0"
        oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-gov-west-1.amazonaws.com/id/EXAMPLE1234567890"
      }
    }
  }

  expect_failures = [var.existing_monitoring_role_arn]
}

run "rejects_a_malformed_monitoring_role_arn" {
  command = plan

  variables {
    deployment_type              = "eks"
    region                       = "us-east-1"
    existing_monitoring_role_arn = "sb-app-db-enhanced-monitoring"
    agents = {
      opa1 = {
        agent_tags        = ["nonprod"]
        vpc_id            = "vpc-0123456789abcdef0"
        oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE1234567890"
      }
    }
  }

  expect_failures = [var.existing_monitoring_role_arn]
}
