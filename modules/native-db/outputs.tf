output "ecs_env_vars" {
  value       = local.ecs_env_vars
  description = "Environment variables for the Superblocks Agent ECS container. Pass as superblocks_agent_environment_variables in the terraform_aws_superblocks root module."
}

output "superblocks_agent_tags" {
  value       = local.superblocks_agent_tags
  description = "Agent tags advertising the profiles this OPA serves. Pass as superblocks_agent_tags in the terraform_aws_superblocks root module so the tags the OPA registers cannot drift from the databases it is configured to provision."
}
