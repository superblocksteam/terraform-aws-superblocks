provider "aws" {
  region = "us-east-1"
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
  source  = "superblocksteam/superblocks/aws"
  version = "~>1.0"

  create_lb   = true
  lb_internal = false

  create_vpc     = false
  vpc_id         = local.vpc_id
  lb_subnet_ids  = local.lb_subnet_ids
  ecs_subnet_ids = local.ecs_subnet_ids
  domain         = "clarkthekoala.com"
  subdomain      = "custom-vpc"

  superblocks_agent_key = "my-superblocks-agent-key"
}

output "agent_host_url" {
  value = module.terraform_aws_superblocks.agent_host_url
}
