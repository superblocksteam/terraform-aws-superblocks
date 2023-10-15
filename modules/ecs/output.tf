output "ecs_security_group_id" {
  value = var.create_sg ? module.ecs_security_group[0].security_group_id : null
}

# The execution agent role
output "superblocks_agent_role" {
  value = aws_iam_role.superblocks_agent_role
}
