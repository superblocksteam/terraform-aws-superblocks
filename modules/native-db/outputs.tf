output "ecs_env_vars" {
  value       = local.ecs_env_vars
  description = "Environment variables for the Superblocks Agent ECS container. Pass as superblocks_agent_environment_variables in the terraform_aws_superblocks root module."
}
