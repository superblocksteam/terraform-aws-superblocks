# Seeds state at the addresses a deployment created with v0.2.x carries, so the
# `moved` blocks in the root module have something to move. Only the resources
# those blocks target are declared -- this is not a faithful copy of v0.2.2.
#
# `modules/dns` was renamed to `modules/certs` in v1.0.0, and the ECS module
# lost the `count` that `deploy_in_ecs` used to drive.

variable "domain" {
  type = string
}

variable "subdomain" {
  type = string
}

variable "name_prefix" {
  type = string
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

output "certificate_arn" {
  value = module.dns[0].certificate_arn
}

output "ecs_cluster_id" {
  value = module.ecs[0].cluster_id
}

output "ecs_agent_role_id" {
  value = module.ecs[0].agent_role_id
}
