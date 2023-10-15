variable "region" {
  type = string
  validation {
    condition     = length(var.region) > 0
    error_message = "Variable `region` cannot null."
  }
}

variable "name_prefix" {
  type    = string
  default = "superblocks"
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "subnet_ids" {
  type = list(string)
  validation {
    condition     = length(var.subnet_ids) > 0
    error_message = "Subnet ids are required for ECS service."
  }
}

variable "security_group_ids" {
  type = list(string)
}

variable "target_group_arns" {
  type = list(string)
}

variable "ecs_cluster_capacity_providers" {
  type    = list(string)
  default = ["FARGATE"]
}

variable "container_image" {
  type = string
}

variable "container_environment" {
  type    = list(map(string))
  default = []
}

variable "container_port" {
  type    = number
  default = "8080"
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
  type    = number
  default = "1"
}

variable "container_max_capacity" {
  type    = number
  default = "5"
}

variable "container_scale_up_when_cpu_pct_above" {
  type    = number
  default = "50"
}

variable "container_scale_up_when_memory_pct_above" {
  type    = number
  default = "50"
}

variable "task_role_arn" {
  type        = string
  default     = null
  description = "ARN of IAM role that allows the agent container task to make calls to other AWS services. This can be leveraged for using Superblocks integrations like S3, DynamoDB, etc."
}

variable "create_sg" {
  type    = bool
  default = true
}

variable "vpc_id" {
  type        = string
  default     = ""
  description = "This is only required if you are creating the default security group."
}

variable "load_balancer_sg_ids" {
  type    = list(string)
  default = []
}

variable "sg_egress_with_cidr_blocks" {
  type = list(map(string))
  default = [
    {
      from_port   = 0
      to_port     = 65535
      protocol    = "-1"
      description = "All egress traffic"
      cidr_blocks = "0.0.0.0/0"
    }
  ]
}

variable "additional_ecs_execution_task_policy_arns" {
  type        = list(string)
  default     = []
  description = "List of ARNs of Additional iam policy to attach to the ECS execution role"
}
