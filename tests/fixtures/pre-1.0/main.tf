# Seeds state at the addresses a deployment created before v1.0.0 carries, so
# the `moved` blocks have something to move. Only the resources those blocks
# target are declared -- this is not a faithful copy of v0.2.2.
#
# `modules/dns` was renamed to `modules/certs` in v1.0.0, the ECS module lost
# the `count` that `deploy_in_ecs` used to drive, v1.2.0 renamed the IAM policy
# attachment, and v1.3.2 renamed the load balancer target group.

variable "domain" {
  type = string
}

variable "subdomain" {
  type = string
}

variable "name_prefix" {
  type = string
}

variable "create_lb" {
  type        = bool
  default     = false
  description = "Seed the pre-1.3.2 load balancer too, including the listener that references the certificate."
}

variable "lb_subnet_ids" {
  type    = list(string)
  default = []
}

variable "vpc_id" {
  type    = string
  default = null
}

module "dns" {
  count  = 1
  source = "./dns"

  zone_name   = var.domain
  record_name = var.subdomain
}

module "ecs" {
  count  = 1
  source = "./ecs"

  name_prefix = var.name_prefix
}

module "lb" {
  count  = var.create_lb ? 1 : 0
  source = "./lb"

  name_prefix     = var.name_prefix
  subnet_ids      = var.lb_subnet_ids
  vpc_id          = var.vpc_id
  certificate_arn = module.dns[0].certificate_arn
}

output "certificate_arn" {
  value = module.dns[0].certificate_arn
}

output "ecs_cluster_id" {
  value = module.ecs[0].cluster_id
}

output "ecs_agent_role_id" {
  value = module.ecs[0].agent_role_id
}

output "ecs_policy_attachment_id" {
  value = module.ecs[0].policy_attachment_id
}

output "lb_target_group_arn" {
  value = var.create_lb ? module.lb[0].target_group_arn : null
}
