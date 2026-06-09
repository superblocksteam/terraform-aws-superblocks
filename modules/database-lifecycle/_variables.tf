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
  description = "VPC ID passed through to database module baseInputs."
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnet IDs passed through to database module baseInputs."
}

variable "environments" {
  type        = list(string)
  description = "Superblocks environment classes served by this OPA (edit, preview, production)."
}

variable "profiles" {
  type        = list(string)
  description = "Profile names this OPA serves within each environment class."
}

variable "isolation" {
  type        = string
  default     = "instance_per_app"
  description = "Database isolation mode for the customer wrapper module."
}

variable "module_source" {
  type        = string
  description = "Terraform module source for ensure/retire database operations."
}

variable "module_version" {
  type        = string
  default     = ""
  description = "Terraform module version for ensure/retire database operations."
}

variable "secret_prefix" {
  type        = string
  description = "Allowed Secrets Manager ARN prefix for RDS-managed credentials."
}

variable "supported_operations" {
  type = list(string)
  default = [
    "ensure_database",
    "migrate_schema",
    "retire_database",
  ]
  description = "Lifecycle operations advertised by this OPA."
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
