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

variable "superblocks_agent_http_port" {
  type        = number
  default     = "8080"
  description = "The http port number used by Superblocks Agent container instance"
}

variable "superblocks_agent_grpc_port" {
  type        = number
  default     = "8081"
  description = "The grpc port number used by Superblocks Agent container instance"
}

variable "superblocks_agent_image" {
  type        = string
  default     = "ghcr.io/superblocksteam/agent"
  description = "The docker image used by Superblocks Agent container instance"
}

variable "superblocks_repository_credentials_secret_arn" {
  type        = string
  default     = null
  description = "ARN of the secret that contains the credentials for the private repository that contains the agent image. This is necessary if you are using a private repository to host a custom image."
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

variable "superblocks_agent_quotas_default_api_timeout" {
  type        = string
  default     = "600000"
  description = "The default api timeout in milliseconds."
}

variable "superblocks_grpc_msg_req_max" {
  type        = string
  default     = "30000000"
  description = "The maximum message size in bytes allowed to be received by the gRPC server. This is used to prevent malicious clients from sending large messages to cause memory exhaustion."
}

variable "superblocks_timeout" {
  type        = string
  default     = "10000000000"
  description = "The maximum amount of time in nanoseconds before a request is aborted. This applies for http requests against the Superblocks server and does not apply to the execution time limit of a workload."
}

variable "superblocks_log_level" {
  type        = string
  default     = "info"
  description = "Logging level for the superblocks agent. Accepted values are 'debug', 'info', 'warn', 'error', 'fatal', 'panic'."
}

variable "superblocks_agent_handle_cors" {
  type        = bool
  default     = true
  description = "Whether to enable CORS support for the Superblocks Agent. This is required if you don't have a reverse proxy in front of the agent that handles CORS. This will allow CORS for all origins."
}

variable "superblocks_agent_environment_variables" {
  type        = list(map(string))
  default     = []
  description = "Environment variables that will be passed to the Superblocks Agent container(s). This can be specified in the form of [{name = \"key\", value = \"value\"}]."
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


variable "create_dns" {
  type        = bool
  default     = true
  description = "Whether to create the DNS record for this loadbalancer with the agent URL."
}

variable "create_lb_sg" {
  type        = bool
  default     = true
  description = "Whether to create default loadbalancer security group or not."
}

variable "lb_security_group_ids" {
  type        = list(string)
  default     = []
  description = "Specify additional security groups to associate with the load balancer. This will be joined with the default security group if created."
}

variable "lb_sg_ingress_with_cidr_blocks" {
  type = list(map(string))
  default = [
    {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      description = "HTTPS"
      cidr_blocks = "0.0.0.0/0"
    },
    {
      from_port   = 8443
      to_port     = 8443
      protocol    = "tcp"
      description = "HTTPS"
      cidr_blocks = "0.0.0.0/0"
    }
  ]
  description = "Specify ingress rules for the load balancer. Only used if create_lb_sg is set to true."
}

variable "lb_sg_egress_with_cidr_blocks" {
  type = list(map(string))
  default = [
    {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      description = "All Egress"
      cidr_blocks = "0.0.0.0/0"
    }
  ]
  description = "Specify egress rules for the load balancer. Only used if create_lb_sg is set to true."
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
# Certificate
#################################################################
variable "create_certs" {
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

variable "certificate_arn" {
  type        = string
  default     = null
  description = <<EOF
    This should be the arn of a valid ACM certificate arn.
    It's required if 'create_certificate' is set to false
  EOF
}

variable "private_zone" {
  type        = bool
  default     = false
  description = <<EOF
    Indicates whether the zone is private or not.
  EOF
}

#################################################################
# ECS
#################################################################

variable "lb_target_group_http_arns" {
  type        = list(string)
  default     = []
  description = <<EOF
    These are the additional arns of http load balancer target group that's used for Superblocks Agent.
    Required if 'create_lb' is set to false.
  EOF
}

variable "lb_target_group_grpc_arns" {
  type        = list(string)
  default     = []
  description = <<EOF
    These are the additional arns of grpc load balancer target group that's used for Superblocks Agent.
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

variable "ecs_security_group_ids" {
  type        = list(string)
  default     = []
  description = "Specify additional security groups to associate with the ECS cluster. This will be joined with the default security group if created."
}

variable "create_ecs_sg" {
  type        = bool
  default     = true
  description = "Whether to create default security group for ECS or not."
}

variable "allowed_load_balancer_sg_ids" {
  type        = list(string)
  default     = []
  description = "Specify any number of loadbalancer security group ids to allow traffic from. If the loadbalancer is created via this module, it is automatically added. Only used when create_ecs_sg is set to true."
}

variable "ecs_sg_egress_with_cidr_blocks" {
  type = list(map(string))
  default = [
    {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      description = "All egress traffic"
      cidr_blocks = "0.0.0.0/0"
    }
  ]
  description = "Specify egress rules for the ECS cluster. Only used if create_ecs_sg is set to true."
}

variable "additional_ecs_execution_task_policy_arns" {
  type        = list(string)
  default     = []
  description = "List of ARNs of Additional iam policy to attach to the ECS execution role"
}
