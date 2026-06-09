output "vpc_id" {
  value = local.vpc_id
}

output "lb_subnet_ids" {
  value = local.lb_subnet_ids
}

output "ecs_subnet_ids" {
  value = local.ecs_subnet_ids
}

output "lb_security_group_id" {
  value = var.create_lb ? module.lb[0].lb_security_group_id : null
}

output "ecs_security_group_id" {
  value = module.ecs.ecs_security_group_id
}

output "lb_dns_name" {
  value = var.create_lb ? module.lb[0].dns_name : null
}

output "agent_host_url" {
  value = local.agent_host_url
}

# The ecs execution agent role
output "ecs_execution_agent_role" {
  value = module.ecs.superblocks_agent_role
}

output "database_lifecycle_profiles_json" {
  description = "Rendered SUPERBLOCKS_DATABASE_LIFECYCLE_PROFILES JSON when database_lifecycle_enabled is true."
  value       = try(module.database_lifecycle[0].profiles_json, null)
}

output "database_lifecycle_state_bucket_name" {
  description = "S3 bucket for lifecycle worker Terraform state when database_lifecycle_enabled is true."
  value       = try(module.database_lifecycle[0].state_bucket_name, null)
}

output "database_lifecycle_task_policy_arn" {
  description = "IAM policy ARN for lifecycle worker permissions when database_lifecycle_enabled is true."
  value       = try(module.database_lifecycle[0].task_policy_arn, null)
}
