provider "aws" {
  region = "us-east-1"
}

module "terraform_aws_superblocks" {
  source  = "superblocksteam/superblocks/aws"
  version = "~>1.0"

  lb_internal = false

  create_vpc = true
  domain     = "clarkthekoala.com"
  subdomain  = "example-simple-public-agent"

  superblocks_agent_key = "my-superblocks-agent-key"
}

output "agent_host_url" {
  value = module.terraform_aws_superblocks.agent_host_url
}
