################################################################################
# State moves for deployments created before v1.2.0
#
# See ../../moved.tf for why renames need to be recorded as state moves.
################################################################################

# v1.1.1 -> v1.2.0: renamed to match the naming of the role and policy it joins,
# and given a `count` so additional policies can be attached.
#
# The `[0]` is load-bearing. The old resource had no `count`, so its state
# instance has no key, and a whole-resource move preserves instance keys -- it
# would land on an address this resource no longer declares, and Terraform would
# silently plan the destroy/create this block exists to prevent. `local.policies`
# is `concat([aws_iam_policy.superblocks_agent_policy.arn], ...)`, so index 0 is
# the policy the old resource attached.
moved {
  from = aws_iam_role_policy_attachment.policy-attach
  to   = aws_iam_role_policy_attachment.superblocks_agent_policy_attachment[0]
}
