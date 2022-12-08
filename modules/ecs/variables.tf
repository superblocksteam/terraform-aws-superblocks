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
  validation {
    condition     = length(var.security_group_ids) > 0
    error_message = "Security group ids are required for ECS service."
  }
}

variable "target_group_arn" {
  type = string
}

variable "ecs_cluster_capacity_providers" {
  type    = list(string)
  default = ["FARGATE"]
}

variable "container_image" {
  type = string
}

variable "container_environment" {
  type    = string
  default = ""
}

variable "container_port" {
  type    = number
  default = "8020"
}

variable "container_cpu" {
  type        = number
  default     = "512"
  description = "Amount of CPU units. 1024 units = 1 vCPU(virtual CPU core)"
}

variable "container_memory" {
  type        = number
  default     = "1024"
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
