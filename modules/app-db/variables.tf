variable "connector_role_arn" {
  type        = string
  description = "ARN of the connector IAM role (from the app-db-prereqs module output agents[<name>].connector_role_arn). Used to authenticate against RDS via IAM at query time."
}

variable "state_bucket_name" {
  type        = string
  description = "Name of the shared S3 state bucket (from the app-db-prereqs module output state_bucket_name). Shared across all OPAs in the same region."
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
  description = "Prefix that namespaces this OPA's OpenTofu state within the shared S3 bucket. Pass the app-db-prereqs module output agents[<agent_name>].key_prefix — that module's IAM grants the lifecycle worker access under that prefix only, so a hand-written value that differs fails every state read/write with AccessDenied. Override the prefix itself on the prereqs agents entry, not here. Logical database state lands under <key_prefix>/logical/{{profile}}/... and physical instance state under <key_prefix>/physical/{{profile}}/..."

  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]+(/[a-zA-Z0-9._-]+)*$", var.key_prefix))
    error_message = "key_prefix must be one or more slash-separated segments of letters, digits, dots, underscores, or hyphens (e.g. \"app-db/opa1\"). Wildcards, empty segments, and leading or trailing slashes are not permitted — app-db-prereqs applies the same rule before granting IAM on the prefix."
  }
}

variable "agent_name" {
  type        = string
  description = "Stable name for this OPA deployment (the agents map key from app-db-prereqs, e.g. \"opa1\"). Used as the physical database pool identity. Must be unique within your AWS account and must not change once databases exist."

  validation {
    condition     = can(regex("^[a-z0-9]{1,15}$", var.agent_name))
    error_message = "agent_name must be 1–15 lowercase alphanumeric characters (matching the agents map key constraint in app-db-prereqs)."
  }
}

variable "agent_tags" {
  type        = list(string)
  description = "Agent profile tags this OPA is registered with (from the app-db-prereqs module output agents[<name>].agent_tags). Used to populate the lifecycle config profiles — must match the agent_tags the OPA advertises to Superblocks. Wildcards are not permitted."

  validation {
    condition     = length(var.agent_tags) > 0
    error_message = "agent_tags must contain at least one profile tag."
  }

  validation {
    condition = (
      alltrue([for t in var.agent_tags : can(regex("^[a-z0-9-]{1,15}$", t))]) &&
      length(var.agent_tags) == length(toset(var.agent_tags))
    )
    error_message = "Each agent_tag must be a unique 1-15 lowercase alphanumeric or hyphen string (matching the agents[].agent_tags constraint in app-db-prereqs). Commas and mixed case break the comma-delimited registration string."
  }
}

variable "pool" {
  type = object({
    max_databases                  = optional(number, 100)
    min_available_capacity_percent = optional(number, 20)
  })
  default     = {}
  description = "Shared physical pool configuration. max_databases sets the maximum number of logical databases a single RDS instance can hold before a new instance is automatically provisioned (default 100). min_available_capacity_percent is the proactive shared-pool floor published as databaseLifecycle:capacityPolicies (V2). Defaults to 20 to match helm/agent. Set to 0 to disable proactive enqueue; omitting the field from a hand-written SUPERBLOCKS_DATABASE_LIFECYCLE_CONFIG leaves ensure-fallback-only, but this module always renders the field."

  validation {
    condition     = var.pool.max_databases > 0 && floor(var.pool.max_databases) == var.pool.max_databases
    error_message = "pool.max_databases must be a positive integer."
  }

  validation {
    condition = (
      var.pool.min_available_capacity_percent >= 0 &&
      var.pool.min_available_capacity_percent <= 100 &&
      floor(var.pool.min_available_capacity_percent) == var.pool.min_available_capacity_percent
    )
    error_message = "pool.min_available_capacity_percent must be an integer between 0 and 100."
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

    `tags` are applied to every database, security group, security-group rule, and parameter group the OPA provisions. The ownership pair `superblocks:owned = "true"` and `aws-apn-id` is always merged over whatever you pass, and the lifecycle worker adds the `ManagedBy`, `AgentName`, and `Vpc` tags its own IAM conditions require.

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
