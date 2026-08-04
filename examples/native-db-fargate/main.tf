provider "aws" {
  region = "us-east-1"
}

# -----------------------------------------------------------------------
# Adding native DB to an existing OPA deployment?
#
# Add steps 1 and 2 below to your existing Terraform configuration (the
# same root that manages your OPA ECS task), then update your existing
# terraform-aws-superblocks module block with three new arguments:
#
#   superblocks_agent_tags                  = module.native_db_opa1.superblocks_agent_tags
#   superblocks_agent_role_arn              = module.native_db_prereqs.agents["opa1"].lifecycle_worker_role_arn
#   superblocks_agent_environment_variables = module.native_db_opa1.ecs_env_vars
#
# IMPORTANT: set existing_role_name (in the agents block below) to your
# current ECS task role name so native-db-prereqs attaches its policies to
# that role rather than creating a new one. Replacing superblocks_agent_role_arn
# with a brand-new role drops any permissions your existing integrations rely on.
#
# Do NOT invoke the root module a second time (step 3 below) — that would
# create a duplicate OPA deployment. Update your existing module block instead,
# as shown above.
#
# Deploying a new OPA with native DB from scratch? Follow all three steps.
# -----------------------------------------------------------------------

# Step 1 of 3: bootstrap IAM roles and S3 state bucket.
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
      # Agent tags namespace the DB users provisioned by this OPA. Each tag is
      # hashed into a profile token — the first 16 hex characters of SHA-256 over
      # the lowercased tag — so "nonprod" creates runtime users as
      # sbndb_6fdc0c6b96ee8a74_<application-token>_runtime.
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

  # Optional: reuse an account-level Enhanced Monitoring role created by a
  # prior regional apply of this module. The role name is account-scoped
  # (<name_prefix>-enhanced-monitoring), so a second region must pass the ARN
  # from the first instead of creating another copy.
  # existing_monitoring_role_arn = "arn:aws:iam::123456789012:role/sb-native-db-enhanced-monitoring"

  # Optional: additional tags applied to all resources created by this module.
  tags = {
    Environment = "production"
  }
}

# Step 2 of 3: generate the environment variables the OPA ECS container needs
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
    # Aurora Serverless v2 is the default: capacity scales between min_acu and
    # max_acu with no instance class to size. Omit `deployment` entirely to
    # accept the module defaults, or state the range you want. instance_count
    # = 2 keeps a second warm instance for immediate failover.
    #
    # min_acu = 0 lets a cluster pause when idle. Use it for nonprod, not
    # production.
    deployment = {
      serverless_v2 = {
        instance_count = 2
        max_acu        = 32
        min_acu        = 2
      }
    }

    # Aurora with fixed instances instead of Serverless v2:
    # deployment = {
    #   provisioned = {
    #     instance_class = "db.r6g.large"
    #     instance_count = 2
    #   }
    # }

    # Standalone RDS instead of an Aurora cluster (omit deployment above):
    # allocated_storage = 100
    # instance_class    = "db.t4g.medium"

    vpc_id = "vpc-0123456789abcdef0"

    # Subnets in at least two Availability Zones — required by the DB subnet group.
    subnet_ids = [
      "subnet-0000000000000001",
      "subnet-0000000000000002",
    ]

    # Propagate the same tags applied to IAM and S3 resources above.
    tags = module.native_db_prereqs.tags

    # Enhanced Monitoring runs at 60 seconds by default, and RDS only accepts
    # that alongside a role it can assume. Pass the prerequisite stack's role,
    # or set monitoring_interval = 0 to turn Enhanced Monitoring off.
    monitoring_role_arn = module.native_db_prereqs.enhanced_monitoring_role_arn

    # The OPA ECS task SG — allows it to reach the provisioned database on port
    # 5432. Must be pre-created and passed here (rather than referencing the root
    # module's auto-created ECS SG) because native-db feeds into the root module,
    # making a back-reference a dependency cycle.
    source_security_group_ids = ["sg-your-opa-task-sg"]
  }

  # Optional: override the pool capacity. Default is 100 logical databases per
  # Aurora cluster before a new cluster is automatically provisioned.
  # pool = { max_databases = 50 }
}

# Step 3 of 3: deploy the OPA ECS task, wiring in the native DB role and env
# vars from the two modules above.
#
# Skip this step if you are adding native DB to an existing OPA deployment —
# update your existing terraform-aws-superblocks module block instead (see the
# comment at the top of this file).
#
# Registry path (when consuming from Terraform Registry):
#   source  = "superblocksteam/superblocks/aws"
#   version = "~>1.0"
module "superblocks_opa1" {
  source = "../../"

  # Required inputs for your OPA deployment (fill in your values):
  superblocks_agent_key = "YOUR_AGENT_KEY"
  domain                = "your-agent.example.com"
  vpc_id                = "vpc-0123456789abcdef0"
  ecs_subnet_ids        = ["subnet-0000000000000001", "subnet-0000000000000002"]
  lb_subnet_ids         = ["subnet-0000000000000001", "subnet-0000000000000002"]

  # Native DB additions — wire these in from the modules above.
  superblocks_agent_tags                  = module.native_db_opa1.superblocks_agent_tags
  superblocks_agent_role_arn              = module.native_db_prereqs.agents["opa1"].lifecycle_worker_role_arn
  superblocks_agent_environment_variables = module.native_db_opa1.ecs_env_vars
}

output "agents" {
  value       = module.native_db_prereqs.agents
  description = "Per-agent outputs: lifecycle_worker_role_arn (set as the ECS task role ARN), connector_role_arn, and agent_tags."
}

output "enhanced_monitoring_role_arn" {
  value       = module.native_db_prereqs.enhanced_monitoring_role_arn
  description = "Pass into modules/native-db (or physicalModuleInputs.monitoring_role_arn) so Enhanced Monitoring can attach. Required unless you set monitoring_interval = 0."
}

output "state_bucket_name" {
  value       = module.native_db_prereqs.state_bucket_name
  description = "S3 bucket used by the OPA lifecycle workers to store OpenTofu state."
}

