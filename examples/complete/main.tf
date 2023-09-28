provider "aws" {
  region = "us-east-1"
}

module "terraform_aws_superblocks" {
  source  = "superblocksteam/superblocks/aws"
  version = "~1.0"

  # This will configure the agent URL to be agent.mycompany.com
  domain    = "mycompany.com"
  subdomain = "agent"

  superblocks_agent_key = "my-superblocks-agent-key"
  # Deprecated: use superblocks_agent_tags instead
  superblocks_agent_environment = "*"

  superblocks_agent_tags = "profile:production"

  superblocks_agent_port = 8080

  superblocks_agent_image = "ghcr.io/superblocksteam/agent:v1.0.0"

  superblocks_server_url = "https://api.superblocks.com"

  name_prefix = "superblocks"

  tags = {
    "my-tag" = "my-value"
  }

  superblocks_agent_data_domain = "app.superblocks.com"

  superblocks_agent_role_arn = "arn:aws:iam::361919038798:role/superblocks-agent-role"

  superblocks_grpc_msg_res_max  = "100000000"
  superblocks_grpc_msg_req_max  = "30000000"
  superblocks_timeout           = "10000000000000"
  superblocks_log_level         = "info"
  superblocks_agent_handle_cors = true

  create_vpc     = false
  vpc_id         = "vpc-1234567890"
  lb_subnet_ids  = ["public-subnet-123", "public-subnet-456"]
  ecs_subnet_ids = ["private-subnet-123", "private-subnet-456"]

  create_lb             = true
  lb_internal           = false
  create_dns            = true
  create_lb_sg          = true
  lb_security_group_ids = ["sg-123"]
  lb_sg_ingress_with_cidr_blocks = [
    {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      description = "HTTPS"
      cidr_blocks = "0.0.0.0/0"
    }
  ]
  lb_sg_egress_with_cidr_blocks = [
    {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      description = "All Egress"
      cidr_blocks = "0.0.0.0/0"
    }
  ]

  create_certs    = false
  certificate_arn = "arn:aws:acm:us-west-2:361919038798:certificate/45193203-ac25-4f0c-8a5f-9c57f0c47262"

  # Not actually used in this example since we are creating the LB as part of this module
  lb_target_group_arn    = "arn:aws:elasticloadbalancing:us-west-2:361919038798:targetgroup/1234567890/1234567890"
  container_cpu          = 1024
  container_memory       = 4096
  container_min_capacity = 1
  container_max_capacity = 5
  ecs_security_group_ids = ["sg-456"]
  create_ecs_sg          = true
  load_balancer_sg_ids   = ["sg-123"]
  ecs_sg_egress_with_cidr_blocks = [
    {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      description = "All egress traffic"
      cidr_blocks = "0.0.0.0/0"
    }
  ]
}
