#################################################################
# Common
#################################################################
variable "superblocks_agent_key" {
  type      = string
  sensitive = true
  validation {
    condition     = length(var.superblocks_agent_key) > 10
    error_message = "The agent key is invalid."
  }
}

variable "superblocks_agent_environment" {
  type        = string
  default     = "*"
  description = <<EOF
    DEPRECATED! Use superblocks_agent_tags instead.
    Use this varible to differentiate Superblocks Agent running environment.
    Valid values are "*", "staging" and "production"
  EOF
}

variable "superblocks_agent_tags" {
  type        = string
  default     = "profile:*"
  description = <<EOF
    Use this variable to specify which profile-specific workloads can be executed on this agent.
    It accepts a comma (and colon) separated string representing key-value pairs, and currently only the "profile" key is used.

    Some examples:
    - To support all API executions:      "profile:*"
    - To support staging and production:  "profile:staging,profile:production"
    - To support only staging:            "profile:staging"
    - To support only production:         "profile:production"
    - To support a custom profile:        "profile:custom_profile_key"
  EOF
}

variable "superblocks_agent_port" {
  type        = number
  default     = "8080"
  description = "The http port number used by Superblocks Agent container instance"
}

variable "superblocks_agent_image" {
  type        = string
  default     = "ghcr.io/superblocksteam/agent"
  description = "The docker image used by Superblocks Agent container instance"
}

variable "superblocks_server_url" {
  type        = string
  default     = "https://api.superblocks.com"
  description = "Superblocks API Server URL"
}

variable "name_prefix" {
  type        = string
  default     = "superblocks"
  description = "This will be prepended to the name of each AWS resource created by this module"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "A series of tags that will be added to each AWS resource created by this module"
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

variable "superblocks_agent_data_domain" {
  type    = string
  default = "app.superblocks.com"
  validation {
    condition     = contains(["app.superblocks.com", "eu.superblocks.com"], var.superblocks_agent_data_domain)
    error_message = "The data domain is invalid. Please use 'app.superblocks.com' or 'eu.superblocks.com'."
  }
  description = "The domain name for the specific Superblocks region that hosts your data."
}

variable "superblocks_agent_role_arn" {
  type        = string
  default     = null
  description = "ARN of IAM role that allows the Superblocks Agent container(s) to make calls to other AWS services. This can be leveraged for using Superblocks integrations like S3, DynamoDB, etc."
}

variable "superblocks_grpc_msg_res_max" {
  type        = string
  default     = "100000000"
  description = "The maximum message size in bytes allowed to be sent by the gRPC server. This is used to prevent malicious clients from sending large messages to cause memory exhaustion."
}

variable "superblocks_grpc_msg_req_max" {
  type        = string
  default     = "30000000"
  description = "The maximum message size in bytes allowed to be received by the gRPC server. This is used to prevent malicious clients from sending large messages to cause memory exhaustion."
}

variable "superblocks_timeout" {
  type        = string
  default     = "10000"
  description = "The maximum amount of time in milliseconds before a request is aborted. This applies for http requests against the Superblocks server and does not apply to the execution time limit of a workload."
}

variable "superblocks_log_level" {
  type        = string
  default     = "info"
  description = "Logging level for the superblocks agent"
}

#################################################################
# VPC
#################################################################
variable "create_vpc" {
  type        = bool
  default     = false
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
  default     = true
  description = "When it's set to false, load balancer is accessible in public network."
}

#################################################################
# DNS & Certificate
#################################################################
variable "create_dns" {
  type        = bool
  default     = true
  description = "Whether to create default HTTPS certificate or not."
}

variable "domain" {
  type        = string
  description = <<EOF
    This is the intended domain name of your Superblocks Agent. This will be used to setup your certificate and loadbalancer and registration of the agent against the Superblocks Server.
  EOF
  validation {
    condition     = length(var.domain) > 0
    error_message = "Variable `domain` is required."
  }
}

variable "subdomain" {
  type        = string
  default     = "superblocks-agent"
  description = <<EOF
    This is the intended subdomain name of your Superblocks Agent. This will be used to setup your certificate and loadbalancer and registration of the agent against the Superblocks Server.
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

variable "dns_ttl" {
  type        = number
  default     = 120
  description = <<EOF
    This is the TTL of the DNS record in seconds that's used for Superblocks Agent.
    It's used if 'create_dns' is set to true
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

variable "container_cpu" {
  type        = number
  default     = "1024"
  description = "Amount of CPU units. 1024 units = 1 vCPU(virtual CPU core)"
}

variable "container_memory" {
  type        = number
  default     = "4096"
  description = "Amount of memory in MiB"
}

variable "container_min_capacity" {
  type        = number
  default     = "1"
  description = "Minimum number of container instances"
}

variable "container_max_capacity" {
  type        = number
  default     = "5"
  description = "Maximum number of container instances"
}
