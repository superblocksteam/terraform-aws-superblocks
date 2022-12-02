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
  source      = "../../"
  region      = var.region
  lb_internal = false
  zone_name   = "clarkthekoala.com"
  record_name = "example-simple-public-agent"

  superblocks_agent_key         = var.superblocks_agent_key
  superblocks_agent_environment = "dev"
  superblocks_agent_image       = "ghcr.io/stefanprodan/podinfo"
  superblocks_agent_port        = "9898"
  #superblocks_agent_image       = "ghcr.io/superblocksteam/superblocks-agent-simplified:ts-opa-simplification"
  #superblocks_agent_port        = "8020"
}
