# The pre-1.2.0 IAM wiring, at the addresses this module's `moved` block moves
# from. `aws_iam_role_policy_attachment.policy-attach` has no `count`, which is
# the whole point: the resource that replaced it does.

variable "name_prefix" {
  type    = string
  default = "superblocks"
}

resource "aws_iam_role" "superblocks_agent_role" {
  name_prefix        = "${var.name_prefix}-agent-role"
  assume_role_policy = "{}"
}

resource "aws_iam_policy" "superblocks_agent_policy" {
  name_prefix = "${var.name_prefix}-agent-policy"
  policy      = "{}"
}

resource "aws_iam_role_policy_attachment" "policy-attach" {
  role       = aws_iam_role.superblocks_agent_role.name
  policy_arn = aws_iam_policy.superblocks_agent_policy.arn
}

output "policy_attachment_id" {
  value = aws_iam_role_policy_attachment.policy-attach.id
}
