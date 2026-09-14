# Upgrading a deployment created before v1.0.0 must move state, not replace it.
#
# v1.0.0 renamed `modules/dns` to `modules/certs` and dropped the `count` the
# `deploy_in_ecs` variable used to drive on the ECS module. v1.2.0 renamed the
# IAM policy attachment and gave the replacement a `count`; v1.3.2 renamed the
# load balancer target group. Without the `moved` blocks Terraform reads every
# one of those as destroy/create. The certificate's destroy is not independent
# -- the ALB listener still references it -- so Terraform reports a cycle
# instead of a plan:
#
#   Error: Cycle: module.dns[0].aws_acm_certificate.superblocks (destroy), ...
#
# See https://github.com/superblocksteam/terraform-aws-superblocks/issues/17
#
# This file applies a fixture that seeds state at the pre-1.0 addresses, then
# applies the current root module over that same state through a shared
# `state_key`. Resource ids are what distinguish a move from a replacement: the
# mock provider issues a fresh id whenever a resource is actually recreated, so
# an unchanged id means the state was moved.
#
# The four `moved` blocks are covered across four files:
#   this one                                   module.dns  -> module.certs
#                                              module.ecs[0] -> module.ecs
#   tests/upgrade_with_listener.tftest.hcl     the cycle shape from #17
#   modules/ecs/tests/                         the IAM attachment, incl. its [0]
#   modules/load-balancer/tests/               the target group rename
# Deleting any `moved` block fails one of them.

mock_provider "aws" {
  mock_data "aws_route53_zone" {
    defaults = {
      zone_id = "Z0123456789ABCDEFGHIJ"
    }
  }

  # domain_validation_options has no mock default of its own, and the module
  # indexes into it -- an empty set would fail before the moves are exercised.
  mock_resource "aws_acm_certificate" {
    defaults = {
      domain_validation_options = [{
        domain_name           = "superblocks-agent.example.com"
        resource_record_name  = "_acme.superblocks-agent.example.com"
        resource_record_type  = "CNAME"
        resource_record_value = "_validation.acm-validations.aws."
      }]
    }
  }

  mock_resource "aws_route53_record" {
    defaults = {
      fqdn = "_acme.superblocks-agent.example.com"
    }
  }

  # These reach the provider's ARN validator, which rejects the mock's
  # generated strings. Only `arn` is pinned; `id` stays generated, and `id` is
  # what the assertions compare.
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

variables {
  domain      = "example.com"
  subdomain   = "superblocks-agent"
  name_prefix = "superblocks"
}

# `create_lb = false` keeps the ALB listener out of this scenario so the mocked
# certificate ARN can stay generated. Pinning it to a fixed valid value, as the
# listener's ARN validation would require, would make it identical before and
# after a replacement -- which is exactly what this assertion has to tell apart.
# tests/upgrade_with_listener.tftest.hcl covers the listener.

run "a_pre_1_0_deployment_is_seeded_at_the_old_addresses" {
  command   = apply
  state_key = "upgrade"

  module {
    source = "./tests/fixtures/pre-1.0"
  }
}

run "the_pre_1_0_state_is_moved_rather_than_recreated" {
  command   = apply
  state_key = "upgrade"

  variables {
    create_lb             = false
    superblocks_agent_key = "test-agent-key-0123456789"
    vpc_id                = "vpc-0123456789abcdef0"
    lb_subnet_ids         = ["subnet-0000000000000001", "subnet-0000000000000002"]
    ecs_subnet_ids        = ["subnet-0000000000000003", "subnet-0000000000000004"]
  }

  assert {
    condition     = module.certs[0].certificate_arn == run.a_pre_1_0_deployment_is_seeded_at_the_old_addresses.certificate_arn
    error_message = "the ACM certificate was replaced instead of moved from module.dns[0] to module.certs[0]; its destroy is what issue #17 reports as a cycle"
  }

  assert {
    condition     = output.ecs_execution_agent_role.id == run.a_pre_1_0_deployment_is_seeded_at_the_old_addresses.ecs_agent_role_id
    error_message = "the ECS agent role was replaced instead of moved from module.ecs[0] to module.ecs"
  }

  # The fourth moved block, on the IAM policy attachment, is asserted in
  # modules/ecs/tests/upgrade_moves.tftest.hcl: the attachment is not exposed
  # through any module output, and a module-level run can reference it directly.
}
