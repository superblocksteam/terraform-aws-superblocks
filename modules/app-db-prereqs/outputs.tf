output "agents" {
  value = {
    for k in keys(var.agents) : k => {
      agent_tags                = var.agents[k].agent_tags
      artifacts_key_prefix      = local.agent_artifacts_key_prefixes[k]
      connector_role_arn        = aws_iam_role.connector[k].arn
      key_prefix                = local.agent_state_key_prefixes[k]
      lifecycle_worker_role_arn = local.agent_role_arns[k]
    }
  }
  description = "Per-agent outputs. For each agent: lifecycle_worker_role_arn (ARN of the lifecycle worker role), connector_role_arn (pass as SUPERBLOCKS_APP_DB_CONNECTOR_ROLE_ARN), agent_tags (pass as agent_tags to the app-db module), key_prefix (the IAM-backed state prefix — pass as key_prefix to the app-db module), and artifacts_key_prefix (optional namespace, empty when unset; pass as Helm artifacts.keyPrefix on EKS or as artifacts_key_prefix to modules/app-db on Fargate). Object grants are [<that prefix>/]<profileToken>/*; kinds are not part of this output."
}

output "artifacts_bucket_name" {
  value       = one(aws_s3_bucket.artifacts[*].bucket)
  description = "Name of the long-lived S3 bucket for data artifacts (imports, exports, and later kinds), or null when create_artifacts_bucket is false. One bucket per module invocation, shared by every agent pointed at it. Objects are partitioned by agents[].artifacts_key_prefix (optional namespace) then profile token; the orchestrator deletes what it is done with. A null or empty value means the OPA does not offer import or export. EKS: Helm artifacts.bucket (top-level, not under databaseLifecycle). Fargate: pass as artifacts_bucket_name to modules/app-db, which emits SUPERBLOCKS_ARTIFACTS_BUCKET and SUPERBLOCKS_ARTIFACTS_REGION."
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
  description = "Tags applied to all resources created by this module, including the reserved ManagedBy, superblocks:owned, and aws-apn-id keys. For Fargate, pass to app-db physical_module_inputs.tags if you want the same inventory keys on runtime resources; app-db re-merges the ownership pair itself. Do not pass this map to Helm databaseLifecycle.physicalModuleTags (optional cost/team tags only)."
}
