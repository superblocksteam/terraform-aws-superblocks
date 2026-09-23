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
    artifacts_key_prefix   = optional(string)
    existing_role_name     = optional(string)
    key_prefix             = optional(string)
    rds_secret_kms_key_arn = optional(string)
  }))
  description = "Map of OPA agent configurations keyed by agent name. The map key is the agent name — used to name IAM roles and must be unique per AWS account. Each agent gets its own lifecycle worker role (or attaches to an existing one via existing_role_name) and connector role; all agents share one S3 state bucket and one artifacts bucket per module invocation. State access is scoped to key_prefix (default app-db/<agent>). artifacts_key_prefix is an optional namespace passed to the OPA as artifacts.keyPrefix when more than one agent shares the bucket (unset for a typical OPA). Object keys are [<that prefix>/]<profileToken>/<kind>/...; Terraform does not name the kind. Pass agents[<name>].key_prefix into the app-db module."

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
      alltrue([for t in agent.agent_tags : length(t) > 0]) &&
      length(agent.agent_tags) == length(toset([for t in agent.agent_tags : lower(t)]))
    ])
    error_message = "Each agent must have at least one non-empty agent_tag, with no duplicates within the agent (comparison is case-insensitive)."
  }

  validation {
    condition = (
      length(flatten([for agent in values(var.agents) : agent.agent_tags])) ==
      length(toset(flatten([for agent in values(var.agents) : [for t in agent.agent_tags : lower(t)]])))
    )
    error_message = "agent_tags must be unique across all agents (comparison is case-insensitive)."
  }

  validation {
    condition     = alltrue([for agent in values(var.agents) : can(regex("^vpc-[0-9a-f]+$", agent.vpc_id))])
    error_message = "Each agent's vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }

  # The prefix is interpolated into an IAM Resource ARN and a StringLike
  # s3:prefix condition, where * and ? are wildcards — "app-db/*" would grant
  # this worker every other agent's state. Allow only literal path segments so
  # the prefix cannot widen the grant it is supposed to narrow.
  validation {
    condition = alltrue([
      for agent in values(var.agents) :
      agent.key_prefix == null || can(regex("^[a-zA-Z0-9._-]+(/[a-zA-Z0-9._-]+)*$", agent.key_prefix))
    ])
    error_message = "Each agent's key_prefix must be one or more slash-separated segments of letters, digits, dots, underscores, or hyphens (e.g. \"app-db/prod-db1\"). Wildcards, empty segments, and leading or trailing slashes are not permitted."
  }

  # The state-bucket policy grants each worker s3:prefix <prefix>/ and
  # <prefix>/*. Two agents sharing a prefix — or one nested under another —
  # would hand each worker the other's state, which is the isolation this
  # module exists to provide.
  validation {
    condition = alltrue([
      for a, agent_a in var.agents : alltrue([
        for b, agent_b in var.agents :
        a == b ? true : !startswith(
          "${coalesce(agent_b.key_prefix, "app-db/${b}")}/",
          "${coalesce(agent_a.key_prefix, "app-db/${a}")}/"
        )
      ])
    ])
    error_message = "Agent key_prefixes must be disjoint: no two agents may share a prefix, and no prefix may nest under another."
  }

  # Interpolated into an IAM Resource ARN and a StringLike s3:prefix condition,
  # where * and ? are wildcards.
  validation {
    condition = alltrue([
      for agent in values(var.agents) :
      agent.artifacts_key_prefix == null || can(regex("^[a-zA-Z0-9._-]+(/[a-zA-Z0-9._-]+)*$", agent.artifacts_key_prefix))
    ])
    error_message = "Each agent's artifacts_key_prefix must be one or more slash-separated segments of letters, digits, dots, underscores, or hyphens (e.g. \"team-a\"). It is an optional namespace in front of the profile token, not a feature kind. Wildcards, empty segments, and leading or trailing slashes are not permitted."
  }

  # Validate the effective IAM prefixes, including the profile-token segment.
  # This permits agents to share an optional namespace when their profile
  # tokens differ, but rejects any configuration where one grant contains
  # another grant.
  validation {
    condition = alltrue(flatten([
      for a_name, agent_a in var.agents : [
        for tag_a in agent_a.agent_tags : alltrue(flatten([
          for b_name, agent_b in var.agents : [
            for tag_b in agent_b.agent_tags :
            a_name == b_name && lower(tag_a) == lower(tag_b) ? true : !startswith(
              "${agent_b.artifacts_key_prefix == null ? "" : "${agent_b.artifacts_key_prefix}/"}${substr(sha256(lower(tag_b)), 0, 16)}/",
              "${agent_a.artifacts_key_prefix == null ? "" : "${agent_a.artifacts_key_prefix}/"}${substr(sha256(lower(tag_a)), 0, 16)}/"
            )
          ]
        ]))
      ]
    ]))
    error_message = "Artifact IAM prefixes must be disjoint after adding each profile token: no worker grant may contain another worker's grant."
  }
}

variable "iam_name_prefix" {
  type        = string
  default     = "sb-app-db"
  description = "Prefix applied to IAM roles and policies created by this module. Defaults to 'sb-app-db'. Max 16 lowercase alphanumeric characters or hyphens."

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,14}[a-z0-9])?$", var.iam_name_prefix))
    error_message = "Variable iam_name_prefix must be 1-16 lowercase alphanumeric characters or hyphens, and must not start or end with a hyphen."
  }
}

variable "s3_name_prefix" {
  type        = string
  default     = "sb-app-db"
  description = "Prefix applied to the OpenTofu state bucket created by this module. Defaults to 'sb-app-db'. Max 16 lowercase alphanumeric characters or hyphens."

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,14}[a-z0-9])?$", var.s3_name_prefix))
    error_message = "Variable s3_name_prefix must be 1-16 lowercase alphanumeric characters or hyphens, and must not start or end with a hyphen."
  }
}

# Like s3_name_prefix for the state bucket, this value identifies the bucket
# owned by one module invocation. Independent invocations in the same account
# and region must use distinct values; separate Terraform states must not
# manage the same bucket. Both bucket names freeze independently after the
# first apply because both resources carry prevent_destroy.
variable "s3_artifacts_name_prefix" {
  type        = string
  default     = "sb-data-artifacts"
  description = "Prefix applied to the artifacts bucket created by this module. Defaults to 'sb-data-artifacts'. Max 20 lowercase alphanumeric characters or hyphens. Separate from s3_name_prefix so each instantiation in an account can pick a unique name before the first apply; both buckets then freeze independently via prevent_destroy. If the deployer role can only CreateBucket under a specific name prefix, set this to a value that matches that allowlist before the first apply."

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,18}[a-z0-9])?$", var.s3_artifacts_name_prefix))
    error_message = "Variable s3_artifacts_name_prefix must be 1-20 lowercase alphanumeric characters or hyphens, and must not start or end with a hyphen."
  }
}

variable "allowed_origins" {
  type        = list(string)
  default     = []
  description = "Browser origins allowed to PUT objects to the artifacts bucket (CORS). The browser must be able to read the ETag of each uploaded part, so this list has to include every origin that hosts the Superblocks UI for this account. A non-empty list requires the deployer role to have s3:PutBucketCORS on the artifacts bucket."

  validation {
    condition = alltrue([
      for origin in var.allowed_origins :
      !strcontains(origin, "*") && can(regex("^https://[A-Za-z0-9.-]+(:[0-9]+)?$", origin))
    ])
    error_message = "Each allowed_origins entry must be an explicit https origin (e.g. \"https://app.superblocks.com\"); wildcard origins and paths are not permitted."
  }
}

variable "artifacts_kms_key_arn" {
  type        = string
  default     = null
  description = "ARN of the customer-managed KMS key for the artifacts bucket (data artifacts such as imports, exports, and later kinds). When provided, that bucket uses SSE-KMS with this key and lifecycle-worker IAM is granted kms:Decrypt, kms:DescribeKey, and kms:GenerateDataKey on this key. When null, the bucket uses AWS account-default encryption (SSE-S3) and no artifacts KMS IAM statement is attached. Independent of kms_key_arn so customer data is not decryptable with the state key."
}

variable "kms_key_arn" {
  type        = string
  default     = null
  description = "ARN of the customer-managed KMS key for the OpenTofu state bucket. When provided, the bucket is configured with SSE-KMS using this key and lifecycle-worker IAM is granted KMS access only on this key. When null, the bucket uses AWS account-default encryption (SSE-S3) and no state-bucket KMS IAM statement is attached."
}

variable "existing_monitoring_role_arn" {
  type        = string
  default     = null
  description = "ARN of an existing account-level RDS Enhanced Monitoring role. When null, the module creates <iam_name_prefix>-enhanced-monitoring. Set this in additional regions so every worker reuses one shared role instead of creating a second copy. The physical database modules take this ARN as monitoring_role_arn; the worker is granted iam:PassRole on it and nothing else. Setting this on a deployment that previously created the role destroys that role: any database still configured with the old ARN loses Enhanced Monitoring until the physical modules are re-pointed at the role you supply here, so re-point them first."

  validation {
    condition     = var.existing_monitoring_role_arn == null || can(regex("^arn:aws:iam::[0-9]{12}:role/([A-Za-z0-9+=,.@_-]+/)*[A-Za-z0-9+=,.@_-]+$", var.existing_monitoring_role_arn))
    error_message = "existing_monitoring_role_arn must be a concrete IAM role ARN in the aws partition, with an optional path and no wildcards. The rest of this module hardcodes arn:aws:, so aws-us-gov and aws-cn ARNs are not supported."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags to apply to all resources created by this module. Three keys are reserved and always overridden: ManagedBy = \"superblocks-app-database-lifecycle\", which the IAM conditions that scope the lifecycle worker's blast radius depend on, plus superblocks:owned = \"true\" and aws-apn-id, the ownership and AWS Partner Network attribution required on every Superblocks-created resource."
}
