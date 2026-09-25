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
  value       = module.ecs.ecs_security_group_id
  description = "Security group the ECS task runs in when create_ecs_sg = true, null otherwise. Pass it to modules/app-db as physical_module_inputs.source_security_group_ids."
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
