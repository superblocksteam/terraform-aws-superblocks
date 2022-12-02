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
  lb_internal   = false

  # Set 'create_certificate' to false and provide your custom certificate arn
  # Certificate can be requested from AWS Certificate Manager
  create_certificate         = false
  certificate_arn            = "YOUR CERTIFICATE ARN"
  superblocks_agent_host_url = "https://custom-cert.clarkthekoala.com"

  superblocks_agent_key         = var.superblocks_agent_key
  superblocks_agent_environment = "dev"
  #superblocks_agent_image       = "ghcr.io/superblocksteam/superblocks-agent-simplified:ts-opa-simplification"
  #superblocks_agent_port        = "8020"
  superblocks_agent_image       = "ghcr.io/stefanprodan/podinfo"
  superblocks_agent_port        = "9898"
}

# Once the agent is deployed, create a CNAME record
# map "custom-cert.clarkthekoala.com" to the value of "lb_dns_name"
output "lb_dns_name" {
  value = module.terraform_aws_superblocks.lb_dns_name
}
