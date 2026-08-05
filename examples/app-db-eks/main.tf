provider "aws" {
  region = "us-east-1"
}

# Bootstrap the IAM roles and S3 state bucket required before the OPA lifecycle
# worker can provision RDS/Aurora instances. Run this once per region.
# EKS customers only need this module — runtime config goes in the Helm chart.
#
# Registry path (when consuming from Terraform Registry):
#   source  = "superblocksteam/superblocks/aws//modules/app-db-prereqs"
#   version = "~>1.0"
module "app_db_prereqs" {
  source = "../../modules/app-db-prereqs"

  deployment_type = "eks"
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

      # ARN of the EKS cluster's OIDC provider. Found in the EKS console under
      # "Configuration > Authentication", or via:
      #   aws eks describe-cluster --name <cluster-name> \
      #     --query "cluster.identity.oidc.issuer" --output text
      oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE1234567890"

      # Optional: Kubernetes namespace and service account name of the OPA pod.
      # Used to scope the OIDC trust policy condition to the specific service account
      # (system:serviceaccount:<namespace>:<service_account_name>). Defaults match
      # the standard Superblocks Helm chart values — only override if you deviate.
      # namespace            = "superblocks"
      # service_account_name = "superblocks-agent"

      # Optional: name of an existing IRSA role to attach lifecycle worker policies
      # to. When omitted, the module creates a new role. Use this when your OPA pod
      # already has an IRSA-annotated role from a prior Helm install (brownfield).
      # The existing role's trust policy is left unchanged.
      # existing_role_name = "my-existing-opa-irsa-role"

      # Optional: ARN of a customer-managed KMS key used to encrypt the RDS-managed
      # master secret in Secrets Manager. When omitted, the secret uses the AWS-managed
      # Secrets Manager key for your account.
      # rds_secret_kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/mrk-..."
    }

    # Example: second OPA in the same region, different EKS cluster.
    # opa2 = {
    #   agent_tags        = ["staging"]
    #   vpc_id            = "vpc-0fedcba9876543210"
    #   oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE0987654321"
    # }
  }

  # Optional: override the default resource name prefix ("sb-app-db").
  # name_prefix = "acme-app-db"

  # Optional: customer-managed KMS key for the OpenTofu state bucket.
  # kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/mrk-..."

  # Optional: reuse an account-level Enhanced Monitoring role created by a
  # prior regional apply of this module. The role name is account-scoped
  # (<name_prefix>-enhanced-monitoring), so a second region must pass the ARN
  # from the first instead of creating another copy.
  # existing_monitoring_role_arn = "arn:aws:iam::123456789012:role/sb-app-db-enhanced-monitoring"

  # Optional: additional tags applied to all resources created by this module.
  tags = {
    Environment = "production"
  }
}

# Wire enhanced_monitoring_role_arn into the OPA Helm chart so physical
# modules can attach Enhanced Monitoring (default monitoring_interval is 60).
# Without this, plans fail the module precondition even though the IAM role
# exists:
#
#   databaseLifecycle:
#     physicalModuleInputs:
#       monitoring_role_arn: <module.app_db_prereqs.enhanced_monitoring_role_arn>
#
# Or opt out with monitoring_interval: 0.

output "agents" {
  value       = module.app_db_prereqs.agents
  description = "Per-agent outputs. For each agent: lifecycle_worker_role_arn (annotate the OPA service account via eks.amazonaws.com/role-arn) and connector_role_arn (pass to OPA Helm chart as SUPERBLOCKS_APP_DB_CONNECTOR_ROLE_ARN)."
}

output "enhanced_monitoring_role_arn" {
  value       = module.app_db_prereqs.enhanced_monitoring_role_arn
  description = "Pass to OPA Helm as databaseLifecycle.physicalModuleInputs.monitoring_role_arn so Enhanced Monitoring can attach. Required unless you set monitoring_interval: 0."
}

output "state_bucket_name" {
  value       = module.app_db_prereqs.state_bucket_name
  description = "S3 bucket used by the OPA lifecycle workers to store OpenTofu state."
}
