# modules/app-db renders verify_database_infra_absence by default, and OPA
# images before v1.53.0 exit at startup when it is present. The root module
# fails the plan for a pinned image older than that instead of shipping a task
# definition that cannot start.

mock_provider "aws" {
  mock_data "aws_region" {
    defaults = {
      name = "us-east-1"
    }
  }
  mock_resource "aws_lb" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/sb/0123456789abcdef"
    }
  }
  mock_resource "aws_lb_target_group" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/sb/0123456789abcdef"
    }
  }
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/sb"
    }
  }
  mock_resource "aws_iam_policy" {
    defaults = {
      arn = "arn:aws:iam::123456789012:policy/sb"
    }
  }
  mock_resource "aws_ecs_cluster" {
    defaults = {
      arn = "arn:aws:ecs:us-east-1:123456789012:cluster/sb"
    }
  }
  mock_resource "aws_ecs_task_definition" {
    defaults = {
      arn = "arn:aws:ecs:us-east-1:123456789012:task-definition/sb:1"
    }
  }
  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:us-east-1:123456789012:log-group:sb"
    }
  }
}

variables {
  superblocks_agent_key = "test-agent-key-0123456789"
  domain                = "example.com"
  create_certs          = false
  create_dns            = false
  create_vpc            = false
  vpc_id                = "vpc-0123456789abcdef0"
  ecs_subnet_ids        = ["subnet-0000000000000001", "subnet-0000000000000002"]
  lb_subnet_ids         = ["subnet-0000000000000001", "subnet-0000000000000002"]

  superblocks_agent_environment_variables = [
    {
      name  = "SUPERBLOCKS_DATABASE_LIFECYCLE_CONFIG"
      value = "{\"engines\":[\"postgres\"],\"operations\":{\"migrate_schema\":{\"backend\":\"native_runner\"},\"verify_database_infra_absence\":{\"backend\":\"native_runner\"}}}"
    },
  ]
}

run "an_image_older_than_v1_53_0_fails_the_plan" {
  command = plan

  variables {
    superblocks_agent_image = "ghcr.io/superblocksteam/agent:v1.46.0"
  }

  expect_failures = [data.aws_region.current]
}

run "an_image_at_v1_53_0_plans" {
  command = plan

  variables {
    superblocks_agent_image = "ghcr.io/superblocksteam/agent:v1.53.0"
  }
}

run "an_untagged_image_plans" {
  command = plan

  variables {
    superblocks_agent_image = "ghcr.io/superblocksteam/agent"
  }
}

run "a_digest_pinned_image_plans" {
  command = plan

  variables {
    superblocks_agent_image = "ghcr.io/superblocksteam/agent@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
  }
}

run "an_old_image_plans_when_the_operation_is_turned_off" {
  command = plan

  variables {
    superblocks_agent_image = "ghcr.io/superblocksteam/agent:v1.46.0"
    superblocks_agent_environment_variables = [
      {
        name  = "SUPERBLOCKS_DATABASE_LIFECYCLE_CONFIG"
        value = "{\"engines\":[\"postgres\"],\"operations\":{\"migrate_schema\":{\"backend\":\"native_runner\"}}}"
      },
    ]
  }
}

run "an_old_image_without_app_db_plans" {
  command = plan

  variables {
    superblocks_agent_image                 = "ghcr.io/superblocksteam/agent:v1.20.0"
    superblocks_agent_environment_variables = []
  }
}
