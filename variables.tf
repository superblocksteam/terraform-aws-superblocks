#################################################################
# Common
#################################################################
variable "region" {
  type = string
  validation {
    condition     = length(var.region) > 0
    error_message = "Variable `region` cannot null."
  }
}

variable "superblocks_agent_key" {
  type      = string
  sensitive = true
  validation {
    # TODO: use regexp to validate agent key
    condition     = length(var.superblocks_agent_key) > 10
    error_message = "The agent key is invalid."
  }
}

variable "superblocks_agent_environment" {
  type    = string
  defaule = "*"
}

variable "superblocks_agent_host_url" {
  type    = string
  default = ""
}

variable "superblocks_agent_port" {
  type    = number
  default = "8020"
}

variable "superblocks_agent_image" {
  type    = string
  default = "ghcr.io/superblocksteam/agent"
}

variable "superblocks_server_url" {
  type    = string
  default = "https://app.superblocks.com"
}

variable "name_prefix" {
  type    = string
  default = "superblocks"
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "deploy_in_ecs" {
  type        = bool
  default     = true
  description = <<EOF
    Whether to deploy Superblocks Agent to ECS Fargate.
    Currently, this is the only option to deploy On-Premise Agent.
    We will support other deployment options in the future.
  EOF
}

#################################################################
# VPC
#################################################################
variable "create_vpc" {
  type        = bool
  default     = true
  description = "Whether to create default VPC or not."
}

variable "vpc_id" {
  type        = string
  default     = null
  description = "Set VPC id if 'create_vpc' is set to false."
}

variable "lb_subnet_ids" {
  type        = list(string)
  default     = []
  description = "Set subnet ids for load balander if 'create_vpc' is set to false."
}

variable "ecs_subnet_ids" {
  type        = list(string)
  default     = []
  description = "Set subnet ids for AWS ECS service if 'create_vpc' is set to false."
}

#################################################################
# Security Group
#################################################################
variable "create_sg" {
  type        = bool
  default     = true
  description = "Whether to create default security group or not."
}

variable "security_group_ids" {
  type        = list(string)
  default     = []
  description = "Specify security group ids if 'create_sg' is set to false."
}

#################################################################
# Load Balancer
#################################################################
variable "create_lb" {
  type        = bool
  default     = true
  description = "Whether to create default load balancer or not."
}

variable "lb_internal" {
  type        = bool
  default     = false
  description = "When it's set to false, load balancer is accessible in public network."
}

#################################################################
# Certificate
#################################################################
variable "create_certificate" {
  type        = bool
  default     = true
  description = "Whether to create default HTTPS certificate or not."
}

variable "zone_name" {
  type        = string
  default     = null
  description = <<EOF
    This should be the name of a Route53 hosted zone in the AWS account.
    It's required if you want Superblocks to create the certificate.
  EOF
}

variable "record_name" {
  type        = string
  default     = "superblocks-agent"
  description = <<EOF
    This is the record name for Superblocks Agent.
    With "record_name" and "dns_name" being set,
    the full agent domain will be "superblocks-agent.mydomain.com"
    It's required if you want Superblocks to create the certificate.
  EOF
}

variable "lb_dns_name" {
  type        = string
  default     = null
  description = <<EOF
    This is the DNS name of load balancer that's used for Superblocks Agent.
    To create the certificate, an Alias record will be created.
    That record will be pointed to this DNS name.
    Required if you want Superblocks to create the certificate and 'create_lb' is set to false.
  EOF
}

variable "lb_zone_id" {
  type        = string
  default     = null
  description = <<EOF
    This is the DNS zone id of load balancer that's used for Superblocks Agent.
    Required if you want Superblocks to create the certificate and 'create_lb' is set to false.
  EOF
}

variable "certificate_arn" {
  type        = string
  default     = null
  description = <<EOF
    This should be the arn of a valid ACM certificate arn.
    It's required if 'create_certificate' is set to false
  EOF
}

#################################################################
# ECS
#################################################################
variable "lb_target_group_arn" {
  type        = string
  default     = null
  description = <<EOF
    This is the arn of load balancer target group that's used for Superblocks Agent.
    Required if 'create_lb' is set to false.
  EOF
}
