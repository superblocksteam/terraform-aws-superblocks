output "agents" {
  value = {
    for k in keys(var.agents) : k => {
      lifecycle_worker_role_arn = local.agent_role_arns[k]
      connector_role_arn        = aws_iam_role.connector[k].arn
      agent_tags                = var.agents[k].agent_tags
    }
  }
  description = "Per-agent outputs. For each agent: lifecycle_worker_role_arn (ARN of the lifecycle worker role), connector_role_arn (pass as SUPERBLOCKS_NATIVE_DB_CONNECTOR_ROLE_ARN), and agent_tags (pass as agent_tags to the native-db module)."
}

output "state_bucket_name" {
  value       = aws_s3_bucket.tofu_state.id
  description = "Name of the S3 bucket used for OpenTofu state, shared across all agents in this module invocation."
}

output "tags" {
  value       = var.tags
  description = "Tags applied to all resources created by this module. Pass to the native-db module's physical_module_inputs.tags to tag RDS instances with the same values."
}
