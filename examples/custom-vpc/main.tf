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

# Create your own VPC or use the sub-module in this package
module "vpc" {
  source = "../../modules/vpc"

  cidr_block      = "10.0.0.0/20"
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  private_subnets = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
}

locals {
  vpc_id         = module.vpc.id
  lb_subnet_ids  = module.vpc.lb_subnet_ids
  ecs_subnet_ids = module.vpc.ecs_subnet_ids
}

module "terraform_aws_superblocks" {
  source      = "../../"
  lb_internal = false

  vpc_id         = local.vpc_id
  lb_subnet_ids  = local.lb_subnet_ids
  ecs_subnet_ids = local.ecs_subnet_ids
  domain         = "clarkthekoala.com"
  subdomain      = "custom-vpc"

  superblocks_agent_key = var.superblocks_agent_key
}

output "agent_host_url" {
  value = module.terraform_aws_superblocks.agent_host_url
}
