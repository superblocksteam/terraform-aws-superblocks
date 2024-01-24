provider "aws" {
  region = "us-east-1"
}

module "terraform_aws_superblocks" {
  source  = "superblocksteam/superblocks/aws"
  version = "~>1.0"

  create_vpc = true
  domain     = "clarkthekoala.com"
  subdomain  = "custom-cert"

  create_lb       = true
  lb_internal     = false
  certificate_arn = "arn:aws:acm:us-east-1:361919038798:certificate/12345678-1234-1234-1234-123456789012"

  superblocks_agent_key = "my-superblocks-agent-key"
}

# Once the agent is deployed, create a CNAME record
# map "custom-cert.clarkthekoala.com" to the value of "lb_dns_name"
output "lb_dns_name" {
  value = module.terraform_aws_superblocks.lb_dns_name
}

output "agent_host_url" {
  value = module.terraform_aws_superblocks.agent_host_url
}
