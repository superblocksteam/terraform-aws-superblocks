variable "deployment_type" {
  type        = string
  description = "Deployment type: 'eks' or 'fargate'. Applies to all agents in this module invocation."

  validation {
    condition     = contains(["eks", "fargate"], var.deployment_type)
    error_message = "Variable `deployment_type` must be 'eks' or 'fargate'."
  }
}

variable "region" {
  type        = string
  description = "AWS region where resources are created."

  validation {
    condition     = length(var.region) > 0
    error_message = "Variable `region` cannot be empty."
  }
}

variable "agents" {
  type = map(object({
    agent_tags             = list(string)
    vpc_id                 = string
    oidc_provider_arn      = optional(string)
    namespace              = optional(string, "superblocks")
    service_account_name   = optional(string, "superblocks-agent")
    existing_role_name     = optional(string)
    rds_secret_kms_key_arn = optional(string)
  }))
  description = "Map of OPA agent configurations keyed by agent name. The map key is the agent name — used to name IAM roles and must be unique per AWS account. Each agent gets its own lifecycle worker role (or attaches to an existing one via existing_role_name) and connector role; all agents share one S3 state bucket per module invocation, with object access scoped to app-db/<agent>/."

  validation {
    condition     = length(var.agents) > 0
    error_message = "At least one agent must be provided."
  }

  validation {
    condition     = alltrue([for k in keys(var.agents) : can(regex("^[a-z0-9]{1,15}$", k))])
    error_message = "Agent names (map keys) must be 1-15 lowercase alphanumeric characters."
  }

  validation {
    condition = alltrue([
      for agent in values(var.agents) :
      length(agent.agent_tags) > 0 &&
      alltrue([for t in agent.agent_tags : can(regex("^[a-z0-9-]{1,15}$", t))]) &&
      length(agent.agent_tags) == length(toset(agent.agent_tags))
    ])
    error_message = "Each agent must have at least one unique agent_tag; tag names must be 1-15 lowercase alphanumeric characters or hyphens."
  }

  validation {
    condition     = alltrue([for agent in values(var.agents) : can(regex("^vpc-[0-9a-f]+$", agent.vpc_id))])
    error_message = "Each agent's vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}

variable "name_prefix" {
  type        = string
  default     = "sb-app-db"
  description = "Prefix applied to all IAM roles, policies, and the S3 state bucket created by this module. Defaults to 'sb-app-db'. Override when your organization requires a specific naming convention. Max 16 characters (combined with region (≤14) and account ID (12) the bucket name stays under S3's 63-character limit)."

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,14}[a-z0-9]$", var.name_prefix))
    error_message = "Variable name_prefix must be 2-16 lowercase alphanumeric characters or hyphens, and must not start or end with a hyphen."
  }
}

variable "kms_key_arn" {
  type        = string
  default     = null
  description = "ARN of the KMS key for the OpenTofu state bucket. When provided, the bucket is configured with SSE-KMS using this key and lifecycle-worker IAM is granted KMS access only on this key. When null, the bucket uses AWS account-default encryption (SSE-S3) and no state-bucket KMS IAM statement is attached."
}

variable "existing_monitoring_role_arn" {
  type        = string
  default     = null
  description = "ARN of an existing account-level RDS Enhanced Monitoring role. When null, the module creates <name_prefix>-enhanced-monitoring. Set this in additional regions so every worker reuses one shared role instead of creating a second copy. The physical database modules take this ARN as monitoring_role_arn; the worker is granted iam:PassRole on it and nothing else. Setting this on a deployment that previously created the role destroys that role: any database still configured with the old ARN loses Enhanced Monitoring until the physical modules are re-pointed at the role you supply here, so re-point them first."

  validation {
    condition     = var.existing_monitoring_role_arn == null || can(regex("^arn:aws:iam::[0-9]{12}:role/([A-Za-z0-9+=,.@_-]+/)*[A-Za-z0-9+=,.@_-]+$", var.existing_monitoring_role_arn))
    error_message = "existing_monitoring_role_arn must be a concrete IAM role ARN in the aws partition, with an optional path and no wildcards. The rest of this module hardcodes arn:aws:, so aws-us-gov and aws-cn ARNs are not supported."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags to apply to all resources created by this module. Do not set ManagedBy — the module always enforces ManagedBy = \"superblocks-app-database-lifecycle\", which is required for IAM conditions that scope the lifecycle worker's blast radius."
}
