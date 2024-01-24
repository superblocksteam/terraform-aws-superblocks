# You may want to use this deploy this if you wish to deploy both an internal and external load balancer. This would allow you to call the agent for workflows from within your VPC and not need to roundtrip from the public internet.

provider "aws" {
  region = "us-east-1"
}

module "internal_cert" {
  source = "superblocksteam/superblocks/aws//modules/certs"

  zone_name   = "clarkthekoala.com"
  record_name = "private-agent"
}

module "internal_lb" {
  source  = "superblocksteam/superblocks/aws//modules/load-balancer"
  version = "~1.0"

  name_prefix = "private"
  internal    = true
  vpc_id      = module.terraform_aws_superblocks.vpc_id

  subnet_ids         = module.terraform_aws_superblocks.lb_subnet_ids
  security_group_ids = ["sg-1234567890"]

  create_dns  = true
  zone_name   = "clarkthekoala.com"
  record_name = "private-agent"

  create_sg = true

  certificate_arn = module.internal_cert.certificate_arn
}

module "terraform_aws_superblocks" {
  source  = "superblocksteam/superblocks/aws"
  version = "~>1.0"

  lb_internal = false

  create_vpc = true
  domain     = "clarkthekoala.com"
  subdomain  = "public-agent"

  lb_target_group_arns = [module.internal_lb.target_group_arn]
  allowed_load_balancer_sg_ids = [module.internal_lb.lb_security_group_id]

  superblocks_agent_key = "my-superblocks-agent-key"
}

output "agent_host_url" {
  value = module.terraform_aws_superblocks.agent_host_url
}
