output "dns_name" {
  value = aws_lb.superblocks.dns_name
}

output "zone_id" {
  value = aws_lb.superblocks.zone_id
}

output "target_group_arn" {
  value = aws_lb_target_group.superblocks.arn
}
