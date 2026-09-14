# The pre-1.3.2 target group, at the address this module's `moved` block moves
# from. v1.3.2 renamed it to `http` when the gRPC target group was added.

variable "name_prefix" {
  type    = string
  default = "superblocks"
}

variable "vpc_id" {
  type = string
}

resource "aws_lb_target_group" "superblocks" {
  name        = "${var.name_prefix}-target-group"
  port        = 8080
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  lifecycle {
    create_before_destroy = true
  }
}

output "target_group_id" {
  value = aws_lb_target_group.superblocks.id
}
