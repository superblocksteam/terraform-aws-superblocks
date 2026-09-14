# v1.3.2 split the single target group into an HTTP and a gRPC one, renaming
# `aws_lb_target_group.superblocks` to `aws_lb_target_group.http`. Without the
# `moved` block in moved.tf the rename reads as destroy/create.
#
# Asserted at module level because the target group's id is not exposed through
# any module output -- only its ARN is, and the ARN has to be pinned here (see
# below), which would make the comparison vacuous.
#
# `arn` is pinned on the load balancer and the target groups because the
# listeners hand those to the provider's ARN validator, which rejects the mock's
# generated strings. `id` is left generated, and `id` is what the assertion
# compares: the mock issues a fresh one whenever a resource is really recreated.

mock_provider "aws" {
  mock_resource "aws_lb" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/sb/1111111111111111"
    }
  }

  mock_resource "aws_lb_target_group" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/sb/2222222222222222"
    }
  }
}

variables {
  vpc_id = "vpc-0123456789abcdef0"
}

run "a_pre_1_3_2_deployment_is_seeded_at_the_old_address" {
  command   = apply
  state_key = "upgrade"

  module {
    source = "./tests/fixtures/pre-1.3.2"
  }
}

run "the_target_group_is_moved_rather_than_recreated" {
  command   = apply
  state_key = "upgrade"

  variables {
    internal           = true
    subnet_ids         = ["subnet-0000000000000001", "subnet-0000000000000002"]
    security_group_ids = []
    create_sg          = false
    create_dns         = false
  }

  assert {
    condition     = aws_lb_target_group.http.id == run.a_pre_1_3_2_deployment_is_seeded_at_the_old_address.target_group_id
    error_message = "the HTTP target group was replaced instead of moved from aws_lb_target_group.superblocks to aws_lb_target_group.http"
  }
}
