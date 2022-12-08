provider "aws" {
  region = var.region
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "superblocks_agent_key" {
  type      = string
  default   = "<YOUR_AGENT_KEY>"
  sensitive = true
}

module "terraform_aws_superblocks" {
  source      = "../../"
  lb_internal = false

  create_vpc = true
  domain     = "clarkthekoala.com"
  subdomain  = "custom-cert"

  create_dns      = false
  certificate_arn = "<YOUR_CERTIFICATE_ARN>"

  superblocks_agent_key = var.superblocks_agent_key
}

# Once the agent is deployed, create a CNAME record
# map "custom-cert.clarkthekoala.com" to the value of "lb_dns_name"
output "lb_dns_name" {
  value = module.terraform_aws_superblocks.lb_dns_name
}

output "agent_host_url" {
  value = module.terraform_aws_superblocks.agent_host_url
}
