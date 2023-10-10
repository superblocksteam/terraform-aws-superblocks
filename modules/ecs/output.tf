output "ecs_security_group_id" {
  value = var.create_sg ? module.ecs_security_group[0].security_group_id : null
}

output "ecs_service_id" {
  value = aws_ecs_service.superblocks.id
}
