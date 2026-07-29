provider "aws" {
  region = "us-east-1"
}

# Step 1 of 2 for Fargate customers: bootstrap IAM roles and S3 state bucket.
# Pass the outputs of this module into modules/native-db (step 2), which
# generates the ecs_env_vars wired into the OPA ECS task definition.
#
# Registry path (when consuming from Terraform Registry):
#   source  = "superblocksteam/superblocks/aws//modules/native-db-prereqs"
#   version = "~>1.0"
module "native_db_prereqs" {
  source = "../../modules/native-db-prereqs"

  deployment_type = "fargate"
  region          = "us-east-1"

  # One entry per OPA deployment. The map key is the agent name — used to name
  # IAM roles and must be unique per AWS account (max 15 characters).
  agents = {
    opa1 = {
      # Agent tags namespace the DB users provisioned by this OPA.
      # A tag "nonprod" creates runtime users as sbndb_nonprod_<db-id>_runtime.
      # Must match the superblocks_agent_tags configured for this OPA.
      agent_tags = ["nonprod", "production"]

      # VPC the lifecycle worker is allowed to provision RDS/Aurora into.
      vpc_id = "vpc-0123456789abcdef0"

      # Optional: name of an existing ECS task IAM role to attach lifecycle worker
      # policies to. When omitted, the module creates a new role. Use this when
      # your OPA ECS task already has a role you want to reuse (brownfield).
      # existing_role_name = "my-existing-opa-task-role"

      # Optional: ARN of a customer-managed KMS key used to encrypt the RDS-managed
      # master secret in Secrets Manager. When omitted, the secret uses the AWS-managed
      # Secrets Manager key for your account.
      # rds_secret_kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/mrk-..."
    }

    # Example: second OPA in the same region. No state_bucket_name wiring needed —
    # all agents in this module invocation share the same S3 bucket automatically.
    # opa2 = {
    #   agent_tags = ["staging"]
    #   vpc_id     = "vpc-0fedcba9876543210"
    # }
  }

  # Optional: override the default resource name prefix ("sb-native-db").
  # IAM roles are named <name_prefix>-<agent_name>-*; the S3 state bucket is
  # named <name_prefix>-<region>-<account_id>.
  # Max 16 characters. Only needed when your org enforces a naming convention.
  # name_prefix = "acme-native-db"

  # Optional: customer-managed KMS key for the OpenTofu state bucket.
  # When omitted, the bucket uses AWS account-default encryption (SSE-S3).
  # kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/mrk-..."

  # Optional: additional tags applied to all resources created by this module.
  tags = {
    Environment = "production"
  }
}

# Step 2 of 2: generate the environment variables the OPA ECS container needs
# to run the lifecycle worker. Call this once per OPA. Pass ecs_env_vars as
# superblocks_agent_environment_variables in the terraform-aws-superblocks root
# module that manages the ECS task definition.
#
# Registry path (when consuming from Terraform Registry):
#   source  = "superblocksteam/superblocks/aws//modules/native-db"
#   version = "~>1.0"
module "native_db_opa1" {
  source = "../../modules/native-db"

  # Wired directly from native-db-prereqs outputs.
  agent_name         = "opa1"
  connector_role_arn = module.native_db_prereqs.agents["opa1"].connector_role_arn
  agent_tags         = module.native_db_prereqs.agents["opa1"].agent_tags
  state_bucket_name  = module.native_db_prereqs.state_bucket_name

  region = "us-east-1"

  # Namespaces this OPA's OpenTofu state within the shared S3 bucket.
  # Must be unique per OPA. Using the agent name as a suffix is recommended.
  key_prefix = "native-db/opa1"

  physical_module_inputs = {
    instance_class    = "db.t4g.medium"
    allocated_storage = 100

    vpc_id = "vpc-0123456789abcdef0"

    # Subnets in at least two Availability Zones — required by the DB subnet group.
    subnet_ids = [
      "subnet-0000000000000001",
      "subnet-0000000000000002",
    ]

    # Propagate the same tags applied to IAM and S3 resources above.
    tags = module.native_db_prereqs.tags

    # Optional: restrict which security groups (e.g. your OPA task SG) can reach
    # the RDS instances over port 5432.
    # source_security_group_ids = ["sg-0123456789abcdef0"]
  }

  # Optional: override the pool capacity. Default is 100 logical databases per
  # physical RDS instance before a new instance is automatically provisioned.
  # pool = { max_databases = 50 }
}

output "agents" {
  value       = module.native_db_prereqs.agents
  description = "Per-agent outputs: lifecycle_worker_role_arn (set as the ECS task role ARN), connector_role_arn, and agent_tags."
}

output "state_bucket_name" {
  value       = module.native_db_prereqs.state_bucket_name
  description = "S3 bucket used by the OPA lifecycle workers to store OpenTofu state."
}

output "opa1_ecs_env_vars" {
  value       = module.native_db_opa1.ecs_env_vars
  description = "Pass as superblocks_agent_environment_variables in the terraform-aws-superblocks root module for the opa1 ECS task definition."
}
