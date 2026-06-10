variable "name_prefix" {
  type        = string
  description = "Prefix for lifecycle state bucket, lock table, and IAM policy names."
}

variable "region" {
  type        = string
  description = "AWS region for lifecycle Terraform state and RDS provisioning."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to lifecycle supporting resources."
}

variable "vpc_id" {
  type        = string
  description = "VPC ID passed through to the physical database module baseInputs."
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnet IDs passed through to the physical database module baseInputs."
}

variable "environments" {
  type        = list(string)
  description = "Superblocks environment classes served by this OPA (edit, preview, production)."
}

variable "profiles" {
  type        = list(string)
  description = "Profile names this OPA serves within each environment class."
}

variable "module_source" {
  type        = string
  default     = "app.terraform.io/superblocks/postgres-managed-database/aws"
  description = "Terraform module source for ensure/retire database operations (shared pool logical module)."
}

variable "physical_module_source" {
  type        = string
  default     = "git::ssh://git@github.com/superblocksteam/terraform//modules/native-database/aws-rds-managed-instance?ref=main"
  description = "Terraform module source for ensure_physical_database_instance."
}

variable "module_version" {
  type        = string
  default     = ""
  description = "Terraform module version for ensure/retire database operations (registry sources only)."
}

variable "credential_secret_prefix" {
  type        = string
  description = "Path prefix for shared-pool credential secrets (ensure_database module baseInputs)."
}

variable "secrets_manager_allowed_prefix" {
  type        = string
  description = "Allowed Secrets Manager ARN prefix for IAM and credentialResolver."
}

variable "physical_capacity_max" {
  type        = number
  default     = 8
  description = "Maximum databases per physical RDS instance when provisioning new pools."
}

variable "physical_security_class" {
  type        = string
  default     = "standard"
  description = "Security class passed to the physical database module."
}

variable "supported_operations" {
  type = list(string)
  default = [
    "ensure_database",
    "ensure_physical_database_instance",
    "migrate_schema",
    "retire_database",
  ]
  description = "Lifecycle operations advertised by this OPA. migrate_schema is native_runner on the worker."
}

variable "supported_engines" {
  type = list(string)
  default = [
    "postgres",
  ]
  description = "Database engines supported by this OPA."
}

variable "task_role_arn" {
  type        = string
  default     = null
  description = "Optional ECS task role ARN to attach the lifecycle IAM policy."
}

variable "profile_id" {
  type        = string
  default     = ""
  description = "Optional EnvironmentProfile id in the rendered JSON."
}
