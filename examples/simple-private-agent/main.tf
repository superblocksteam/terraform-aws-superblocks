provider "aws" {
  region = var.region
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "superblocks_agent_key" {
  type      = string
  default   = "YOUR AGENT KEY"
  sensitive = true
}

module "terraform_aws_superblocks" {
  source        = "../../"
  region        = var.region
  # Use internal load balancer, so that it's only accessible in the same VPC
  lb_internal   = true
  zone_name     = "clarkthekoala.com"
  record_name   = "example-simple-private-agent"

  superblocks_agent_key         = var.superblocks_agent_key
  superblocks_agent_environment = "dev"
  #superblocks_agent_image       = "ghcr.io/superblocksteam/superblocks-agent-simplified:ts-opa-simplification"
  #superblocks_agent_port        = "8020"
  superblocks_agent_image       = "ghcr.io/stefanprodan/podinfo"
  superblocks_agent_port        = "9898"
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

output "agent_host_url" {
  value = module.terraform_aws_superblocks.agent_host_url
}
