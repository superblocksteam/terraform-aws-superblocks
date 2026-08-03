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

run "grants_native_database_observability_permissions" {
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
        "logs:TagResource",
        "logs:UntagResource",
      ] :
      contains(one([
        for statement in jsondecode(aws_iam_policy.lifecycle_worker_observability["opa1"].policy).Statement :
        statement.Action if statement.Sid == "CloudWatchLogGroupsForNativeDatabases"
      ]), action)
    ])
    error_message = "The worker must be able to manage the log groups the physical modules declare explicitly."
  }

  assert {
    condition = jsonencode(one([
      for statement in jsondecode(aws_iam_policy.lifecycle_worker_observability["opa1"].policy).Statement :
      statement.Resource if statement.Sid == "CloudWatchLogGroupsForNativeDatabases"
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
      statement.Action if statement.Sid == "CloudWatchLogGroupsForNativeDatabases"
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
      ]) == "monitoring.rds.amazonaws.com"
    )
    error_message = "Enhanced Monitoring attach requires iam:PassRole, scoped to the shared monitoring role and to RDS monitoring alone."
  }

  assert {
    condition = (
      aws_iam_role.enhanced_monitoring[0].name == "superblocks-native-db-monitoring" &&
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
    condition     = output.enhanced_monitoring_role_arn == local.monitoring_role_arn
    error_message = "The monitoring role ARN must be exported so operators can pass it as monitoring_role_arn to the physical modules."
  }
}

run "reuses_an_existing_monitoring_role" {
  command = plan

  variables {
    deployment_type              = "eks"
    region                       = "us-west-2"
    existing_monitoring_role_arn = "arn:aws:iam::123456789012:role/platform/superblocks-native-db-monitoring"
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
    ]) == "arn:aws:iam::123456789012:role/platform/superblocks-native-db-monitoring"
    error_message = "A worker that reuses an existing monitoring role must be able to pass that role."
  }

  assert {
    condition     = output.enhanced_monitoring_role_arn == "arn:aws:iam::123456789012:role/platform/superblocks-native-db-monitoring"
    error_message = "The monitoring role output must expose the existing role when one is supplied."
  }
}
