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
  value = module.ecs[0].ecs_security_group_id
}

output "lb_dns_name" {
  value = local.lb_dns_name
}

output "agent_host_url" {
  value = local.agent_host_url
}
