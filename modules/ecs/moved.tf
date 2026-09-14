################################################################################
# State moves for deployments created before v1.2.0
#
# See ../../moved.tf for why renames need to be recorded as state moves.
################################################################################

# v1.1.1 -> v1.2.0: renamed to match the naming of the role and policy it joins.
moved {
  from = aws_iam_role_policy_attachment.policy-attach
  to   = aws_iam_role_policy_attachment.superblocks_agent_policy_attachment
}
