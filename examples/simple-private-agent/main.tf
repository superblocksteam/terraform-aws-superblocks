provider "aws" {
  region = var.region
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "superblocks_agent_key" {
  type      = string
  default   = "<SUPERBLOCKS_AGENT_KEY>"
  sensitive = true
}

module "terraform_aws_superblocks" {
  source = "../../"

  create_vpc = true
  domain     = "clarkthekoala.com"
  subdomain  = "example-simple-private-agent"

  superblocks_agent_key = var.superblocks_agent_key
}

output "vpc_id" {
  value = module.terraform_aws_superblocks.vpc_id
}

output "lb_subnet_ids" {
  value = module.terraform_aws_superblocks.lb_subnet_ids
}

output "ecs_subnet_ids" {
  value = module.terraform_aws_superblocks.ecs_subnet_ids
}

output "security_group_ids" {
  value = module.terraform_aws_superblocks.security_group_ids
}

output "lb_dns_name" {
  value = module.terraform_aws_superblocks.lb_dns_name
}

output "agent_host_url" {
  value = module.terraform_aws_superblocks.agent_host_url
}
