output "vpc_id" {
  value = local.vpc_id
}

output "lb_subnet_ids" {
  value = local.lb_subnet_ids
}

output "ecs_subnet_ids" {
  value = local.ecs_subnet_ids
}

output "security_group_ids" {
  value = local.security_group_ids
}

output "lb_dns_name" {
  value = local.lb_dns_name
}

output "agent_host_url" {
  value = local.agent_host_url
}
