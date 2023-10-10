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
  value = module.lb[0].lb_security_group_id
}

output "ecs_security_group_id" {
  value = module.ecs.ecs_security_group_id
}

output "lb_dns_name" {
  value = module.lb[0].dns_name
}

output "agent_host_url" {
  value = local.agent_host_url
}

output "ecs_service_id" {
  value = module.ecs.ecs_service_id
}
