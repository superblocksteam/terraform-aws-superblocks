# The resources from v0.2.2 `modules/ecs` this fixture needs: stable identities
# to prove the module kept its state when `count` was removed in v1.0.0.

variable "name_prefix" {
  type = string
}

resource "aws_ecs_cluster" "superblocks" {
  name = "${var.name_prefix}-cluster"
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_iam_role" "superblocks_agent_role" {
  name_prefix        = "${var.name_prefix}-agent-role"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

output "cluster_id" {
  value = aws_ecs_cluster.superblocks.id
}

output "agent_role_id" {
  value = aws_iam_role.superblocks_agent_role.id
}
