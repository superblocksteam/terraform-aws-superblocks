data "aws_caller_identity" "current" {}

locals {
  # Module sources relative to the dispatch working directory. The Superblocks
  # OPA image vendors these modules at a fixed path — customers do not configure
  # them.
  logical_module_source  = "./modules/postgres-managed-database"
  physical_module_source = "./modules/aws-rds-managed-instance"

  # SSL cert path baked into the Superblocks OPA image.
  ssl_root_cert = "/etc/ssl/certs/aws-rds-global-bundle.pem"

  # S3 backend base config shared by all operations. The per-operation `key`
  # is set via merge() below so that logical and physical state land under
  # separate prefixes in the same bucket.
  s3_backend_base = {
    stateBackend = "s3"
    bucket       = var.state_bucket_name
    region       = var.region
    use_lockfile = true
  }

  # Physical module inputs forwarded to ensure_physical_database_instance.
  # publicly_accessible is always false — the lifecycle worker IAM policy
  # enforces this at create time regardless of module input.
  physical_inputs = {
    allocated_storage         = var.physical_module_inputs.allocated_storage
    allowed_cidr_blocks       = var.physical_module_inputs.allowed_cidr_blocks
    backup_retention_period   = var.physical_module_inputs.backup_retention_period
    delete_automated_backups  = var.physical_module_inputs.delete_automated_backups
    deletion_protection       = var.physical_module_inputs.deletion_protection
    instance_class            = var.physical_module_inputs.instance_class
    multi_az                  = var.physical_module_inputs.multi_az
    publicly_accessible       = false
    skip_final_snapshot       = var.physical_module_inputs.skip_final_snapshot
    source_security_group_ids = var.physical_module_inputs.source_security_group_ids
    subnet_ids                = var.physical_module_inputs.subnet_ids
    tags                      = var.physical_module_inputs.tags
    vpc_id                    = var.physical_module_inputs.vpc_id
  }

  # Logical module inputs shared by ensure_database and retire_database.
  logical_inputs = {
    auth_mode          = "aws_iam_role"
    connector_role_arn = var.connector_role_arn
    postgres_sslmode   = "verify-full"
    postgres_sslrootcert = local.ssl_root_cert
  }

  # Terraform config shared by ensure_database and retire_database (same
  # logical backend key and module).
  logical_terraform = {
    backend = merge(local.s3_backend_base, {
      key = "${var.key_prefix}/logical/{{environment}}/{{profile}}/{{resource_key}}.tfstate"
    })
    credentialResolver = { runtime = "aws_secrets_manager", region = var.region }
    moduleSelectors = {
      postgres = {
        source = local.logical_module_source
        inputs = local.logical_inputs
      }
    }
  }

  lifecycle_operations = {
    ensure_database = {
      backend = "terraform"
      physicalDatabase = {
        mode               = "shared_pool"
        provisionOperation = "ensure_physical_database_instance"
        onExhausted        = "provision"
        capacityMax        = var.pool.max_databases
        securityClass      = "standard"
      }
      terraform = local.logical_terraform
    }

    ensure_physical_database_instance = {
      backend = "terraform"
      terraform = {
        backend = merge(local.s3_backend_base, {
          key = "${var.key_prefix}/physical/{{environment}}/{{profile}}/{{resource_key}}.tfstate"
        })
        credentialResolver = { runtime = "aws_secrets_manager", region = var.region }
        moduleSelectors = {
          postgres = {
            source = local.physical_module_source
            inputs = local.physical_inputs
          }
        }
      }
    }

    # Schema migrations run natively inside the OPA process — no Terraform.
    migrate_schema = { backend = "native_runner" }

    # retire_database reuses the logical Terraform root so tofu destroy targets
    # the same state as ensure_database.
    retire_database = {
      backend   = "terraform"
      terraform = local.logical_terraform
    }
  }

  # One entry covers all profiles this OPA serves. Profiles must be explicit
  # (no wildcard) and must match the agent_tags declared in native-db-prereqs.
  lifecycle_config = {
    entries = [
      {
        profiles   = var.agent_tags
        engines    = ["postgres"]
        operations = local.lifecycle_operations
      }
    ]
  }

  # Scope the secrets refresolver to only RDS-managed master secrets in this
  # account and region. The lifecycle worker reads these to connect as the
  # admin user when provisioning logical databases.
  allowed_ref_prefixes = [
    "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:rds!db-",
    "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:rds!cluster-",
  ]

  ecs_env_vars = [
    {
      name  = "SUPERBLOCKS_ORCHESTRATOR_DATABASE_LIFECYCLE_WORKER_ENABLED"
      value = "true"
    },
    {
      name  = "SUPERBLOCKS_DATABASE_LIFECYCLE_ROOT_DIR"
      value = "/var/lib/superblocks/database-lifecycle"
    },
    {
      name  = "SUPERBLOCKS_DATABASE_LIFECYCLE_TERRAFORM_BIN"
      value = "/usr/local/bin/tofu"
    },
    {
      name  = "SUPERBLOCKS_DATABASE_LIFECYCLE_POLL_INTERVAL"
      value = "5s"
    },
    {
      name  = "SUPERBLOCKS_DATABASE_LIFECYCLE_ALLOWED_RESOURCE_TYPES"
      value = "aws_db_instance,aws_db_subnet_group,aws_secretsmanager_secret,aws_secretsmanager_secret_version,aws_security_group,aws_security_group_rule,postgresql_database,postgresql_default_privileges,postgresql_grant,postgresql_role,postgresql_schema,random_id,terraform_data"
    },
    {
      name  = "SUPERBLOCKS_DATABASE_LIFECYCLE_ALLOWED_MODULE_SOURCES"
      value = "${local.logical_module_source},${local.physical_module_source}"
    },
    {
      name  = "SUPERBLOCKS_NATIVE_DB_CONNECTOR_ROLE_ARN"
      value = var.connector_role_arn
    },
    {
      name  = "SUPERBLOCKS_POSTGRES_IAM_ALLOWED_ROLE_ARN_PREFIXES"
      value = jsonencode([var.connector_role_arn])
    },
    {
      name  = "SUPERBLOCKS_DATABASE_LIFECYCLE_SSL_MODE"
      value = "verify-full"
    },
    {
      name  = "SUPERBLOCKS_DATABASE_LIFECYCLE_SSL_ROOT_CERT"
      value = local.ssl_root_cert
    },
    {
      name  = "SUPERBLOCKS_SECRETS_REFRESOLVER_ALLOWED_REF_PREFIXES"
      value = join(",", local.allowed_ref_prefixes)
    },
    {
      name  = "SUPERBLOCKS_DATABASE_LIFECYCLE_CONFIG"
      value = jsonencode(local.lifecycle_config)
    },
  ]
}
