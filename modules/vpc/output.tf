output "id" {
  description = "The ID of the VPC"
  value       = aws_vpc.this.id
}

output "lb_subnet_ids" {
  value       = aws_subnet.public[*].id
}

output "ecs_subnet_ids" {
  value       = aws_subnet.private[*].id
}
