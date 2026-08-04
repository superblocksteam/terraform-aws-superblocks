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
  description = "Prefix that namespaces this OPA's OpenTofu state within the shared S3 bucket. Must be unique per OPA — using the agent name as a suffix is recommended (e.g. \"native-db/prod\"). Logical database state lands under <key_prefix>/logical/{{profile}}/... and physical instance state under <key_prefix>/physical/{{profile}}/..."

  validation {
    condition     = length(var.key_prefix) > 0 && !startswith(var.key_prefix, "/") && !endswith(var.key_prefix, "/")
    error_message = "key_prefix must be non-empty and must not start or end with a slash."
  }
}

variable "agent_name" {
  type        = string
  description = "Stable name for this OPA deployment (the agents map key from native-db-prereqs, e.g. \"opa1\"). Used as the physical database pool identity. Must be unique within your AWS account and must not change once databases exist."

  validation {
    condition     = can(regex("^[a-z0-9]{1,15}$", var.agent_name))
    error_message = "agent_name must be 1–15 lowercase alphanumeric characters (matching the agents map key constraint in native-db-prereqs)."
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
    condition = (
      alltrue([for t in var.agent_tags : can(regex("^[a-z0-9-]{1,15}$", t))]) &&
      length(var.agent_tags) == length(toset(var.agent_tags))
    )
    error_message = "Each agent_tag must be a unique 1-15 lowercase alphanumeric or hyphen string (matching the agents[].agent_tags constraint in native-db-prereqs). Commas and mixed case break the comma-delimited registration string."
  }
}

variable "pool" {
  type = object({
    max_databases = optional(number, 100)
  })
  default     = {}
  description = "Shared physical pool configuration. max_databases sets the maximum number of logical databases a single RDS instance can hold before a new instance is automatically provisioned. Defaults to 100."

  validation {
    condition     = var.pool.max_databases > 0 && floor(var.pool.max_databases) == var.pool.max_databases
    error_message = "pool.max_databases must be a positive integer."
  }
}

variable "physical_module_inputs" {
  type = object({
    allocated_storage        = optional(number)
    allowed_cidr_blocks      = optional(list(string), [])
    backup_retention_period  = optional(number, 7)
    delete_automated_backups = optional(bool, false)
    deletion_protection      = optional(bool, true)
    deployment = optional(object({
      provisioned = optional(object({
        instance_class = optional(string, "db.r6g.large")
        instance_count = optional(number, 2)
      }))
      serverless_v2 = optional(object({
        auto_pause_seconds = optional(number, 300)
        instance_count     = optional(number, 1)
        max_acu            = optional(number, 16)
        min_acu            = optional(number, 0)
      }))
    }))
    instance_class            = optional(string)
    monitoring_interval       = optional(number, 60)
    monitoring_role_arn       = optional(string)
    multi_az                  = optional(bool)
    skip_final_snapshot       = optional(bool, false)
    source_security_group_ids = optional(list(string), [])
    subnet_ids                = list(string)
    tags                      = optional(map(string), {})
    vpc_id                    = string
  })
  description = <<-EOT
    Physical database configuration applied to every database this OPA provisions.

    Aurora PostgreSQL is the default. Leaving `deployment` unset provisions Aurora Serverless v2, which scales between a floor and ceiling of Aurora Capacity Units with no instance class to pick. Set `deployment.serverless_v2` to choose that range, or `deployment.provisioned` to run fixed instances instead. `min_acu = 0` lets a cluster pause when idle — appropriate for nonprod, not production.

    Standalone RDS is opt-in: set `allocated_storage` and `instance_class` (and optionally `multi_az`) instead of `deployment`. Aurora manages storage and failover itself and accepts none of those three.

    publicly_accessible is always false and is not configurable — the lifecycle worker IAM policy enforces it regardless.

    Enhanced Monitoring is on at a 60 second interval, which RDS only accepts alongside an IAM role it can assume. Pass the prerequisite stack's `enhanced_monitoring_role_arn` output as `monitoring_role_arn`, or set `monitoring_interval = 0` to turn Enhanced Monitoring off.
  EOT

  validation {
    condition = (
      var.physical_module_inputs.monitoring_interval == 0 ||
      var.physical_module_inputs.monitoring_role_arn != null
    )
    error_message = "physical_module_inputs.monitoring_role_arn is required unless monitoring_interval is 0. Pass the prerequisite stack's enhanced_monitoring_role_arn output, or set monitoring_interval = 0 to disable Enhanced Monitoring."
  }

  validation {
    condition = (
      (var.physical_module_inputs.allocated_storage == null) ==
      (var.physical_module_inputs.instance_class == null)
    )
    error_message = "physical_module_inputs.allocated_storage and instance_class select standalone RDS and must be set together. Omit both to provision Aurora."
  }

  validation {
    condition = (
      var.physical_module_inputs.multi_az == null ||
      (
        var.physical_module_inputs.allocated_storage != null &&
        var.physical_module_inputs.instance_class != null
      )
    )
    error_message = "physical_module_inputs.multi_az is an RDS-only option and must be set together with allocated_storage and instance_class. Omit multi_az to provision Aurora."
  }

  validation {
    condition = var.physical_module_inputs.deployment == null || (
      var.physical_module_inputs.allocated_storage == null &&
      var.physical_module_inputs.instance_class == null &&
      var.physical_module_inputs.multi_az == null
    )
    error_message = "physical_module_inputs.deployment configures Aurora capacity and cannot be combined with the standalone RDS inputs allocated_storage, instance_class, or multi_az."
  }

  validation {
    condition = var.physical_module_inputs.deployment == null || (
      (var.physical_module_inputs.deployment.provisioned == null ? 0 : 1) +
      (var.physical_module_inputs.deployment.serverless_v2 == null ? 0 : 1)
    ) == 1
    error_message = "physical_module_inputs.deployment must configure exactly one of provisioned or serverless_v2. Omit deployment entirely to accept the Serverless v2 default."
  }

  validation {
    condition     = var.physical_module_inputs.allocated_storage == null || try(var.physical_module_inputs.allocated_storage > 0, false)
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
