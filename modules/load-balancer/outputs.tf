output "dns_name" {
  value = aws_lb.superblocks.dns_name
}

output "zone_id" {
  value = aws_lb.superblocks.zone_id
}

output "target_group_arn" {
  value = aws_lb_target_group.superblocks.arn
}

output "lb_security_group_id" {
  value = var.create_sg ? module.loadbalancer_security_group[0].security_group_id : null
}
