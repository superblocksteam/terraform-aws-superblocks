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
  source      = "../../"
  lb_internal = false

  create_vpc  = true
  zone_name   = "clarkthekoala.com"
  record_name = "example-simple-public-agent"

  superblocks_agent_key = var.superblocks_agent_key
}

output "agent_host_url" {
  value = module.terraform_aws_superblocks.agent_host_url
}
