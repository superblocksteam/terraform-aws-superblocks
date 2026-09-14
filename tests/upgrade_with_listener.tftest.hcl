# The upgrade path with an ALB listener present, which the other suites leave
# out. tests/upgrade_from_pre_1.0.tftest.hcl runs with `create_lb = false` so
# the mocked certificate ARN can stay generated and identity can be compared.
#
# What this file does NOT do is reproduce the `Error: Cycle:` from issue #17,
# and it should not be described as if it does: it passes with the `moved`
# blocks deleted. Two reasons. The fixture's listener sits at the same address
# as the real module's, so it is updated in place rather than replaced, and
# Terraform can order a create-new-cert / update-listener / destroy-old-cert
# sequence without a loop. The reported cycle also names a
# `destroy deposed 35ec1523` object -- a create_before_destroy replacement left
# in flight by an earlier interrupted apply -- which a mocked suite cannot
# recreate.
#
# So this is a smoke test of the upgrade with a load balancer in the picture,
# not a regression test for the cycle. The regression coverage is the id
# comparisons in the other three suites: if the `moved` blocks stop working the
# certificate is destroyed and recreated, and those fail.
#
# Identity is not asserted here. The listener hands `certificate_arn`,
# `load_balancer_arn` and `target_group_arn` to the provider's ARN validator,
# which rejects the mock's generated strings, so they have to be pinned to fixed
# valid values -- which makes them identical before and after a replacement.

mock_provider "aws" {
  mock_data "aws_route53_zone" {
    defaults = {
      zone_id = "Z0123456789ABCDEFGHIJ"
    }
  }

  mock_resource "aws_acm_certificate" {
    defaults = {
      arn = "arn:aws:acm:us-east-1:123456789012:certificate/11111111-1111-1111-1111-111111111111"
      domain_validation_options = [{
        domain_name           = "superblocks-agent.example.com"
        resource_record_name  = "_acme.superblocks-agent.example.com"
        resource_record_type  = "CNAME"
        resource_record_value = "_validation.acm-validations.aws."
      }]
    }
  }

  mock_resource "aws_acm_certificate_validation" {
    defaults = {
      certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/11111111-1111-1111-1111-111111111111"
    }
  }

  mock_resource "aws_route53_record" {
    defaults = {
      fqdn = "_acme.superblocks-agent.example.com"
    }
  }

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
  domain        = "example.com"
  subdomain     = "superblocks-agent"
  name_prefix   = "superblocks"
  vpc_id        = "vpc-0123456789abcdef0"
  lb_subnet_ids = ["subnet-0000000000000001", "subnet-0000000000000002"]
}

run "a_pre_1_0_deployment_with_a_listener_is_seeded" {
  command   = apply
  state_key = "with_lb"

  module {
    source = "./tests/fixtures/pre-1.0"
  }

  variables {
    create_lb = true
  }
}

run "the_upgrade_applies_with_a_listener_present" {
  command   = apply
  state_key = "with_lb"

  variables {
    create_lb             = true
    create_certs          = true
    superblocks_agent_key = "test-agent-key-0123456789"
    ecs_subnet_ids        = ["subnet-0000000000000003", "subnet-0000000000000004"]
  }

  assert {
    condition     = module.certs[0].certificate_arn != null
    error_message = "the certs module produced no certificate after the upgrade"
  }

  assert {
    condition     = module.lb[0].target_group_http_arn != null
    error_message = "the load balancer module produced no HTTP target group after the upgrade"
  }
}
