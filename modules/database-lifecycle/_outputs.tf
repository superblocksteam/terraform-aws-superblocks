output "profiles_json" {
  description = "Deploy-rendered EnvironmentProfile[] JSON for SUPERBLOCKS_DATABASE_LIFECYCLE_PROFILES."
  value       = local.lifecycle_profiles_json
}

output "state_bucket_name" {
  description = "S3 bucket storing per-database Terraform state for the lifecycle worker."
  value       = aws_s3_bucket.lifecycle_state.id
}

output "dynamodb_lock_table_name" {
  description = "DynamoDB table used for Terraform state locking."
  value       = aws_dynamodb_table.terraform_locks.name
}

output "task_policy_arn" {
  description = "IAM policy ARN granting the lifecycle worker access to state, locks, and credentials."
  value       = aws_iam_policy.database_lifecycle_task.arn
}
