output "database_infrastructure_notice" {
  value       = "WARNING: Changing scale_to_zero after App Databases have been provisioned does not update existing physical databases automatically. Contact Superblocks Support to update existing databases and avoid mixed configurations."
  description = "Apply-visible notice for the App Databases beta database infrastructure setting. Re-export this output from the calling root module so operators see it after apply."
}

output "ecs_env_vars" {
  value       = local.ecs_env_vars
  description = "Environment variables for the Superblocks Agent ECS container. Pass as superblocks_agent_environment_variables in the terraform_aws_superblocks root module."
}

output "superblocks_agent_tags" {
  value       = local.superblocks_agent_tags
  description = "Agent tags advertising the profiles this OPA serves. Pass as superblocks_agent_tags in the terraform_aws_superblocks root module so the tags the OPA registers cannot drift from the databases it is configured to provision."
}
