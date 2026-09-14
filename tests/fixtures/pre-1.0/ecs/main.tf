# The resources from the pre-1.0 `modules/ecs` this fixture needs: stable
# identities to prove the module kept its state when `count` was removed in
# v1.0.0, and the policy attachment that v1.2.0 renamed.

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

resource "aws_iam_policy" "superblocks_agent_policy" {
  name_prefix = "${var.name_prefix}-agent-policy"
  policy      = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"],
      "Resource": "*"
    }
  ]
}
EOF
}

# No `count` here: that is the point. v1.2.0 renamed this and gave the
# replacement a `count`, so the move has to name an index.
resource "aws_iam_role_policy_attachment" "policy-attach" {
  role       = aws_iam_role.superblocks_agent_role.name
  policy_arn = aws_iam_policy.superblocks_agent_policy.arn
}

output "cluster_id" {
  value = aws_ecs_cluster.superblocks.id
}

output "agent_role_id" {
  value = aws_iam_role.superblocks_agent_role.id
}

output "policy_attachment_id" {
  value = aws_iam_role_policy_attachment.policy-attach.id
}
