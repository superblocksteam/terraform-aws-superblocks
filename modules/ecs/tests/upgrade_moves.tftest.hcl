# v1.2.0 renamed `aws_iam_role_policy_attachment.policy-attach` to
# `superblocks_agent_policy_attachment` and gave the replacement
# `count = length(local.policies)`.
#
# That count is why the `moved` block in moved.tf has to name `[0]`. The old
# resource had no count, so its state instance has no key, and a whole-resource
# move preserves instance keys -- it would land on an address this resource no
# longer declares, and Terraform plans destroy/create with no error to notice.
# In that window the task execution role carries no logs policy, so a Fargate
# task launching then cannot create its log stream and fails to start.
#
# This is asserted here rather than in the root suite because the attachment is
# not exposed through any module output, and a module-level run can reference
# the resource directly.

mock_provider "aws" {
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/superblocks-agent-role"
    }
  }

  mock_resource "aws_iam_policy" {
    defaults = {
      arn = "arn:aws:iam::123456789012:policy/superblocks-agent-policy"
    }
  }
}

run "a_pre_1_2_deployment_is_seeded_at_the_old_address" {
  command   = apply
  state_key = "upgrade"

  module {
    source = "./tests/fixtures/pre-1.2"
  }
}

run "the_policy_attachment_is_moved_rather_than_recreated" {
  command   = apply
  state_key = "upgrade"

  variables {
    region                 = "us-east-1"
    subnet_ids             = ["subnet-0000000000000003", "subnet-0000000000000004"]
    security_group_ids     = []
    target_group_http_arns = []
    target_group_grpc_arns = []
    container_image        = "superblocks/agent:latest"
    vpc_id                 = "vpc-0123456789abcdef0"
    create_sg              = false
  }

  assert {
    condition     = aws_iam_role_policy_attachment.superblocks_agent_policy_attachment[0].id == run.a_pre_1_2_deployment_is_seeded_at_the_old_address.policy_attachment_id
    error_message = "the IAM policy attachment was replaced instead of moved to superblocks_agent_policy_attachment[0]; check that moved.tf names the index"
  }
}
