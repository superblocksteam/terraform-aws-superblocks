output "ecs_security_group_id" {
  value = var.create_sg ? module.ecs_security_group[0].security_group_id : null
}
