################################################################################
# State moves for deployments created before v1.0.0
#
# Renaming a module, or removing `count` from one, changes the state address of
# every resource inside it. Terraform reads that as "destroy everything at the
# old address, create everything at the new one". For the ACM certificate the
# destroy is not independent: the certificate cannot be destroyed while the ALB
# listener still references it, and the listener cannot be updated until the
# replacement certificate is validated. Terraform reports that as a cycle
# instead of a plan:
#
#   Error: Cycle: module.dns[0].aws_acm_certificate.superblocks (destroy),
#   module.dns[0].aws_route53_record.validation_record (destroy),
#   module.lb[0].aws_lb_listener.superblocks (destroy deposed 35ec1523),
#   module.dns[0].aws_acm_certificate_validation.superblocks (destroy),
#   module.lb[0].aws_lb_listener.superblocks
#
# The blocks below rewrite the addresses in place, so the renames are recorded
# as state moves rather than as destroy/create pairs and the cycle never forms.
# They are no-ops for deployments that never used the old addresses.
#
# See https://github.com/superblocksteam/terraform-aws-superblocks/issues/17
################################################################################

# v0.2.2 -> v1.0.0: `modules/dns` was renamed to `modules/certs`. The contents
# were unchanged; only the directory and the calling block name differ.
moved {
  from = module.dns
  to   = module.certs
}

# v0.2.2 -> v1.0.0: the `deploy_in_ecs` variable was removed along with the
# `count` it drove, so `module.ecs[0]` became `module.ecs`.
moved {
  from = module.ecs[0]
  to   = module.ecs
}
