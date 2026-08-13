output "agents" {
  value = {
    for k in keys(var.agents) : k => {
      agent_tags                = var.agents[k].agent_tags
      connector_role_arn        = aws_iam_role.connector[k].arn
      key_prefix                = local.agent_state_key_prefixes[k]
      lifecycle_worker_role_arn = local.agent_role_arns[k]
    }
  }
  description = "Per-agent outputs. For each agent: lifecycle_worker_role_arn (ARN of the lifecycle worker role), connector_role_arn (pass as SUPERBLOCKS_APP_DB_CONNECTOR_ROLE_ARN), agent_tags (pass as agent_tags to the app-db module), and key_prefix (the IAM-backed state prefix — pass as key_prefix to the app-db module; IAM grants state access under this prefix only)."
}

output "enhanced_monitoring_role_arn" {
  value       = local.monitoring_role_arn
  description = "ARN of the account-level RDS Enhanced Monitoring role. Pass this to the physical database modules as monitoring_role_arn (for example via databaseLifecycle.physicalModuleInputs); without it they reject monitoring_interval > 0 at plan time."
}

output "state_bucket_name" {
  value       = aws_s3_bucket.tofu_state.id
  description = "Name of the S3 bucket used for OpenTofu state, shared across all agents in this module invocation."
}

output "tags" {
  value       = local.tags
  description = "Tags applied to all resources created by this module, including the reserved ManagedBy, superblocks:owned, and aws-apn-id keys. Pass to the app-db module's physical_module_inputs.tags (or databaseLifecycle.physicalModuleTags) so runtime App DB resources carry the same values; app-db also re-enforces the ownership pair independently."
}
