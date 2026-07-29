variable "connector_role_arn" {
  type        = string
  description = "ARN of the connector IAM role (from the native-db-prereqs module output agents[<name>].connector_role_arn). Used to authenticate against RDS via IAM at query time."
}

variable "state_bucket_name" {
  type        = string
  description = "Name of the shared S3 state bucket (from the native-db-prereqs module output state_bucket_name). Shared across all OPAs in the same region."
}

variable "region" {
  type        = string
  description = "AWS region where the S3 state bucket and RDS instances live."

  validation {
    condition     = length(var.region) > 0
    error_message = "region cannot be empty."
  }
}

variable "key_prefix" {
  type        = string
  description = "Prefix that namespaces this OPA's OpenTofu state within the shared S3 bucket. Must be unique per OPA — using the agent name as a suffix is recommended (e.g. \"native-db/prod\"). Logical database state lands under <key_prefix>/logical/... and physical instance state under <key_prefix>/physical/..."

  validation {
    condition     = length(var.key_prefix) > 0 && !startswith(var.key_prefix, "/") && !endswith(var.key_prefix, "/")
    error_message = "key_prefix must be non-empty and must not start or end with a slash."
  }
}

variable "agent_name" {
  type        = string
  description = "Stable name for this OPA deployment (the agents map key from native-db-prereqs, e.g. \"opa1\"). Used as the physical database pool identity. Must be unique within your AWS account and must not change once databases exist."

  validation {
    condition     = can(regex("^[a-z0-9_-]{1,15}$", var.agent_name))
    error_message = "agent_name must be 1–15 lowercase alphanumeric characters, hyphens, or underscores (matching the agents map key constraint in native-db-prereqs)."
  }
}

variable "agent_tags" {
  type        = list(string)
  description = "Agent profile tags this OPA is registered with (from the native-db-prereqs module output agents[<name>].agent_tags). Used to populate the lifecycle config profiles — must match the agent_tags the OPA advertises to Superblocks. Wildcards are not permitted."

  validation {
    condition     = length(var.agent_tags) > 0
    error_message = "agent_tags must contain at least one profile tag."
  }

  validation {
    condition     = !contains(var.agent_tags, "*")
    error_message = "Wildcard '*' is not permitted in agent_tags. Use explicit profile keys."
  }
}

variable "pool" {
  type = object({
    max_databases = optional(number, 100)
  })
  default     = {}
  description = "Shared physical pool configuration. max_databases sets the maximum number of logical databases a single RDS instance can hold before a new instance is automatically provisioned. Defaults to 100."

  validation {
    condition     = var.pool.max_databases > 0
    error_message = "pool.max_databases must be a positive integer."
  }
}

variable "physical_module_inputs" {
  type = object({
    allocated_storage         = number
    allowed_cidr_blocks       = optional(list(string), [])
    backup_retention_period   = optional(number, 7)
    delete_automated_backups  = optional(bool, true)
    deletion_protection       = optional(bool, true)
    instance_class            = string
    multi_az                  = optional(bool, true)
    skip_final_snapshot       = optional(bool, false)
    source_security_group_ids = optional(list(string), [])
    subnet_ids                = list(string)
    tags                      = optional(map(string), {})
    vpc_id                    = string
  })
  description = "Physical database configuration applied to every RDS instance this OPA provisions. publicly_accessible is always false and is not configurable — it is enforced by the lifecycle worker IAM policy regardless."

  validation {
    condition     = var.physical_module_inputs.allocated_storage > 0
    error_message = "physical_module_inputs.allocated_storage must be a positive integer."
  }

  validation {
    condition     = length(var.physical_module_inputs.subnet_ids) >= 2
    error_message = "physical_module_inputs.subnet_ids must contain at least two subnet IDs (the DB subnet group requires subnets in at least two Availability Zones)."
  }

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.physical_module_inputs.vpc_id))
    error_message = "physical_module_inputs.vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}
