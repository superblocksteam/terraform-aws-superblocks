################################################################################
# State moves for deployments created before v1.3.2
#
# See ../../moved.tf for why renames need to be recorded as state moves.
################################################################################

# v1.3.1 -> v1.3.2: the single target group was split into an HTTP and a gRPC
# target group, and `aws_lb_target_group.superblocks` became
# `aws_lb_target_group.http`. The gRPC target group is new and has no
# predecessor to move from.
moved {
  from = aws_lb_target_group.superblocks
  to   = aws_lb_target_group.http
}
