provider "aws" {
  region = "us-east-1"
}

module "terraform_aws_superblocks" {
  source  = "superblocksteam/superblocks/aws"
  version = "~1.0"

  create_vpc = true
  domain     = "clarkthekoala.com"
  subdomain  = "example-simple-private-agent"

  superblocks_agent_key = "my-superblocks-agent-key"
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
