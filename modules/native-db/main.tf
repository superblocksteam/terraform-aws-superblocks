data "aws_caller_identity" "current" {}

locals {
  # Module sources relative to the dispatch working directory. The OPA image
  # vendors these modules at fixed paths; this module pins those paths and does
  # not expose them as inputs. Operators who need a different source write their
  # own SUPERBLOCKS_DATABASE_LIFECYCLE_CONFIG instead of using this module.
  logical_module_source = "./modules/postgres-managed-database"

  # Aurora is the default physical engine, so a caller who states only where the
  # database goes gets a Serverless v2 cluster. Standalone RDS is opt-in through
  # the instance-sizing inputs, which Aurora does not accept; the variable's
  # validation requires them together and forbids mixing them with deployment.
  rds_selected = (
    var.physical_module_inputs.allocated_storage != null ||
    var.physical_module_inputs.instance_class != null
  )

  physical_module_source = (
    local.rds_selected
    ? "./modules/aws-rds-managed-instance"
    : "./modules/aws-aurora-managed-cluster"
  )

  # SSL cert path baked into the Superblocks OPA image.
  ssl_root_cert = "/etc/ssl/certs/aws-rds-global-bundle.pem"

  # Agent tags carry the profiles this OPA serves. The worker reads them from
  # SUPERBLOCKS_ORCHESTRATOR_AGENT_TAGS, which the root module renders from its
  # own superblocks_agent_tags input — so this module derives the string and
  # exposes it for wiring rather than emitting a second copy of that env var.
  superblocks_agent_tags = join(",", [for tag in var.agent_tags : "profile:${tag}"])

  # S3 backend base config shared by all operations. The per-operation `key`
  # is set via merge() below so that logical and physical state land under
  # separate prefixes in the same bucket.
  s3_backend_base = {
    stateBackend = "s3"
    bucket       = var.state_bucket_name
    region       = var.region
    use_lockfile = true
  }

  # Physical inputs both modules accept. publicly_accessible is always false —
  # the lifecycle worker IAM policy enforces this at create time regardless of
  # module input.
  physical_inputs_shared = {
    allowed_cidr_blocks       = var.physical_module_inputs.allowed_cidr_blocks
    backup_retention_period   = var.physical_module_inputs.backup_retention_period
    delete_automated_backups  = var.physical_module_inputs.delete_automated_backups
    deletion_protection       = var.physical_module_inputs.deletion_protection
    monitoring_interval       = var.physical_module_inputs.monitoring_interval
    monitoring_role_arn       = var.physical_module_inputs.monitoring_role_arn
    publicly_accessible       = false
    skip_final_snapshot       = var.physical_module_inputs.skip_final_snapshot
    source_security_group_ids = var.physical_module_inputs.source_security_group_ids
    subnet_ids                = var.physical_module_inputs.subnet_ids
    tags                      = var.physical_module_inputs.tags
    vpc_id                    = var.physical_module_inputs.vpc_id
  }

  # An omitted deployment forwards an empty serverless_v2 object so the Aurora
  # module applies its own Serverless v2 defaults rather than this module
  # restating a capacity range it would then have to keep in sync.
  aurora_deployment_json = (
    var.physical_module_inputs.deployment == null
    ? jsonencode({ serverless_v2 = {} })
    : jsonencode(var.physical_module_inputs.deployment)
  )

  # Aurora and RDS take disjoint capacity arguments and each fails the plan with
  # "Unsupported argument" on the other's, so only the selected set is
  # forwarded. The chosen set round-trips through JSON because a conditional
  # between the two object types would unify them and silently drop keys.
  physical_inputs_json = (
    local.rds_selected
    ? jsonencode(merge(local.physical_inputs_shared,
      {
        allocated_storage = var.physical_module_inputs.allocated_storage
        instance_class    = var.physical_module_inputs.instance_class
      },
      # An unstated multi_az is dropped rather than forwarded as null so the RDS
      # module's own default governs it.
      { for name, value in { multi_az = var.physical_module_inputs.multi_az } : name => value if value != null },
    ))
    : jsonencode(merge(local.physical_inputs_shared, {
      deployment = jsondecode(local.aurora_deployment_json)
    }))
  )

  # Physical module inputs forwarded to ensure_physical_database_instance.
  physical_inputs = jsondecode(local.physical_inputs_json)

  # Logical module inputs shared by ensure_database and retire_database.
  #
  # auth_mode is absent deliberately: the worker sends aws_iam_role itself, and
  # the logical module no longer accepts the input from operators.
  #
  # connector_role_arn is not authored by the caller either — it has one legal
  # value per OPA and arrives as a module input — but it must still reach the
  # logical module, because the worker only advertises managed IAM when the
  # module inputs carry the connector role it was configured with. The Helm
  # path derives it into these inputs the same way.
  logical_inputs = {
    connector_role_arn   = var.connector_role_arn
    postgres_sslmode     = "verify-full"
    postgres_sslrootcert = local.ssl_root_cert
  }

  # Terraform config shared by ensure_database and retire_database (same
  # logical backend key and module).
  logical_terraform = {
    backend = merge(local.s3_backend_base, {
      key = "${var.key_prefix}/logical/{{profile}}/{{resource_key}}.tfstate"
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
          key = "${var.key_prefix}/physical/{{profile}}/{{resource_key}}.tfstate"
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

  # One configuration per OPA: engines and operations sit at the document root.
  # The profiles this OPA serves are deliberately absent — they are declared
  # once as agent tags, and the worker rejects a profiles key here outright so
  # the two can never disagree.
  lifecycle_config = {
    engines    = ["postgres"]
    operations = local.lifecycle_operations
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
    # SUPERBLOCKS_DATABASE_LIFECYCLE_ALLOWED_RESOURCE_TYPES is deliberately
    # unset. The worker's own default mirrors the resource graph of the modules
    # it ships, and an operator-supplied list replaces that default outright
    # rather than extending it — so a hardcoded list here would fail the first
    # plan that creates a resource type a newer module release introduced.
    {
      name  = "SUPERBLOCKS_DATABASE_LIFECYCLE_ALLOWED_MODULE_SOURCES"
      value = "${local.logical_module_source},${local.physical_module_source}"
    },
    {
      name  = "SUPERBLOCKS_DATABASE_LIFECYCLE_AGENT_NAME"
      value = var.agent_name
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
