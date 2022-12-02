output "id" {
  value = module.vpc.vpc_id
}

output "lb_subnet_ids" {
  value = module.vpc.public_subnets
}

output "ecs_subnet_ids" {
  value = module.vpc.private_subnets
}
