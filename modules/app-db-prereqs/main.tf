data "aws_caller_identity" "current" {}

# Look up any existing roles customers provide so we can reference their ARNs.
data "aws_iam_role" "existing" {
  for_each = { for k, agent in var.agents : k => agent.existing_role_name if agent.existing_role_name != null }
  name     = each.value
}

locals {
  # ----------------------------------------------------------------
  # Per-agent role resolution.
  # When existing_role_name is set, use that role; otherwise use the
  # role created by this module for that agent.
  # ----------------------------------------------------------------
  agent_role_names = {
    for k, agent in var.agents : k =>
    agent.existing_role_name != null
    ? agent.existing_role_name
    : aws_iam_role.lifecycle_worker[k].name
  }

  agent_role_arns = {
    for k, agent in var.agents : k =>
    agent.existing_role_name != null
    ? data.aws_iam_role.existing[k].arn
    : aws_iam_role.lifecycle_worker[k].arn
  }

  # ----------------------------------------------------------------
  # Profile tokens.
  #
  # Every database and runtime user the lifecycle worker creates is named
  # sbndb_<profile_token>_<application_token>[_runtime], where profile_token is
  # the first 16 hex characters of SHA-256 over the lowercased data tag. IAM
  # grants must be written against that token, not the tag itself.
  #
  #   printf '%s' nonprod | shasum -a 256 | cut -c1-16  =>  6fdc0c6b96ee8a74
  # ----------------------------------------------------------------
  profile_tokens = {
    for tag in distinct(flatten([for agent in values(var.agents) : agent.agent_tags])) :
    tag => substr(sha256(lower(tag)), 0, 16)
  }

  # ----------------------------------------------------------------
  # Tagging
  # ----------------------------------------------------------------
  managed_by_tag = "superblocks-app-database-lifecycle"
  tags           = merge(var.tags, { ManagedBy = local.managed_by_tag })

  # ----------------------------------------------------------------
  # RDS and EC2 ARN helpers (region + account scoped, not agent scoped)
  # ----------------------------------------------------------------
  rds_prefix = "arn:aws:rds:${var.region}:${data.aws_caller_identity.current.account_id}"
  ec2_prefix = "arn:aws:ec2:${var.region}:${data.aws_caller_identity.current.account_id}"

  rds_resources = {
    cluster          = "${local.rds_prefix}:cluster:sb-*"
    cluster_pg       = "${local.rds_prefix}:cluster-pg:sb-*"
    cluster_pg_all   = "${local.rds_prefix}:cluster-pg:*"
    cluster_snapshot = "${local.rds_prefix}:cluster-snapshot:sb-*"
    db               = "${local.rds_prefix}:db:sb-*"
    pg_sb            = "${local.rds_prefix}:pg:sb-*"
    pg_all           = "${local.rds_prefix}:pg:*"
    snapshot         = "${local.rds_prefix}:snapshot:sb-*"
    subgrp           = "${local.rds_prefix}:subgrp:sb-*"
  }

  # Log groups the physical modules declare explicitly, named
  # /aws/rds/{cluster,instance}/<sb-identifier>/<log type>.
  app_db_cloudwatch_log_group_arn_patterns = [
    "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/rds/cluster/sb-*",
    "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/rds/instance/sb-*",
  ]

  # Regions are wildcarded because one account-level monitoring role serves
  # every region the worker provisions into; aws:SourceAccount is what blocks
  # cross-account use.
  app_db_rds_monitoring_source_arn_patterns = [
    "arn:aws:rds:*:${data.aws_caller_identity.current.account_id}:cluster:sb-*",
    "arn:aws:rds:*:${data.aws_caller_identity.current.account_id}:db:sb-*",
  ]

  # Account-level Enhanced Monitoring role. The physical modules never create
  # it — callers pass this ARN as monitoring_role_arn. Additional regions can
  # reuse an existing role via existing_monitoring_role_arn.
  create_monitoring_role = var.existing_monitoring_role_arn == null
  monitoring_role_arn = (
    local.create_monitoring_role
    ? aws_iam_role.enhanced_monitoring[0].arn
    : var.existing_monitoring_role_arn
  )

  # ----------------------------------------------------------------
  # S3 state bucket ARN (always created, shared across all agents)
  # ----------------------------------------------------------------
  state_bucket_arn = aws_s3_bucket.tofu_state.arn

  # ----------------------------------------------------------------
  # KMS statement for the state bucket (module-level, one shared bucket).
  # When a specific KMS key is provided the Resource is scoped to that key.
  # When null, Resource is * but access is constrained via CalledVia.
  # ----------------------------------------------------------------
  state_bucket_kms_statement = merge(
    {
      Sid    = "StateBucketKms"
      Effect = "Allow"
      Action = [
        "kms:Decrypt",
        "kms:DescribeKey",
        "kms:Encrypt",
        "kms:GenerateDataKey",
        "kms:ReEncryptFrom",
        "kms:ReEncryptTo",
      ]
      Resource = var.kms_key_arn != null ? var.kms_key_arn : "*"
    },
    var.kms_key_arn == null ? {
      Condition = {
        "ForAnyValue:StringEquals" = {
          "aws:CalledVia" = "s3.amazonaws.com"
        }
      }
    } : {}
  )

  # ----------------------------------------------------------------
  # Per-agent OIDC provider URLs (EKS only).
  # ARN format: arn:aws:iam::<account>:oidc-provider/<url>
  # ----------------------------------------------------------------
  oidc_provider_urls = {
    for k, agent in var.agents : k =>
    var.deployment_type == "eks"
    ? replace(agent.oidc_provider_arn, "/^arn:aws:iam::[0-9]+:oidc-provider\\//", "")
    : ""
  }

  # ----------------------------------------------------------------
  # Per-agent trust policies for the lifecycle worker role.
  # EKS uses OIDC web identity; Fargate uses ECS task service principal.
  # ----------------------------------------------------------------
  lifecycle_worker_assume_role_policies = {
    for k, agent in var.agents : k =>
    var.deployment_type == "eks" ? jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect    = "Allow"
          Action    = "sts:AssumeRoleWithWebIdentity"
          Principal = { Federated = agent.oidc_provider_arn }
          Condition = {
            StringEquals = {
              "${local.oidc_provider_urls[k]}:aud" = "sts.amazonaws.com"
            }
            StringLike = {
              "${local.oidc_provider_urls[k]}:sub" = "system:serviceaccount:${agent.namespace}:${agent.service_account_name}"
            }
          }
        }
      ]
      }) : jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect    = "Allow"
          Action    = "sts:AssumeRole"
          Principal = { Service = "ecs-tasks.amazonaws.com" }
        }
      ]
    })
  }

  # ----------------------------------------------------------------
  # Per-agent EC2 VPC statement for CreateSecurityGroup.
  # ec2:VpcID is a single-value condition key on the vpc/ resource type.
  # ----------------------------------------------------------------
  agent_ec2_create_sg_vpc_statements = {
    for k, agent in var.agents : k => [
      {
        Sid      = "Ec2CreateSecurityGroupVpc${replace(agent.vpc_id, "-", "")}"
        Effect   = "Allow"
        Action   = ["ec2:CreateSecurityGroup"]
        Resource = "${local.ec2_prefix}:vpc/${agent.vpc_id}"
        Condition = {
          StringEquals = {
            "ec2:VpcID" = agent.vpc_id
          }
        }
      }
    ]
  }

  # ----------------------------------------------------------------
  # Per-agent KMS statement for RDS-managed master secrets.
  # When a CMK is provided: Resource is scoped to that key.
  # When null: Resource is * (AWS-managed key path; ViaService + context still apply).
  # ----------------------------------------------------------------
  agent_rds_secret_kms_statements = {
    for k, agent in var.agents : k => {
      Sid      = "DecryptRdsManagedSecretKmsKey"
      Effect   = "Allow"
      Action   = ["kms:Decrypt", "kms:DescribeKey"]
      Resource = agent.rds_secret_kms_key_arn != null ? agent.rds_secret_kms_key_arn : "*"
      Condition = {
        StringEquals = {
          "kms:ViaService" = "secretsmanager.${var.region}.amazonaws.com"
        }
        StringLike = {
          "kms:EncryptionContext:SecretARN" = [
            "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:rds!cluster-*",
            "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:rds!db-*",
          ]
        }
      }
    }
  }
}

####################################################################
# Lifecycle Worker IAM Role (one per agent, greenfield only)
#
# Skipped when existing_role_name is set for that agent — policies
# are attached to the provided roles instead.
####################################################################
resource "aws_iam_role" "lifecycle_worker" {
  for_each = { for k, agent in var.agents : k => agent if agent.existing_role_name == null }

  name               = "${var.name_prefix}-${each.key}-lifecycle-worker-${var.region}"
  assume_role_policy = local.lifecycle_worker_assume_role_policies[each.key]

  tags = local.tags
}

# ----------------------------------------------------------------
# Policy: assume the connector role
# ----------------------------------------------------------------
resource "aws_iam_policy" "lifecycle_worker_assume_connector" {
  for_each = var.agents

  name        = "${var.name_prefix}-${each.key}-assume-connector"
  description = "Allows the ${each.key} lifecycle worker to assume its connector role for RDS IAM authentication."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AssumeAppDatabaseConnector"
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = [aws_iam_role.connector[each.key].arn]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lifecycle_worker_assume_connector" {
  for_each   = var.agents
  role       = local.agent_role_names[each.key]
  policy_arn = aws_iam_policy.lifecycle_worker_assume_connector[each.key].arn
}

# ----------------------------------------------------------------
# Policy: OpenTofu S3 state backend (shared bucket, per-agent policy)
# ----------------------------------------------------------------
resource "aws_iam_policy" "lifecycle_worker_state_bucket" {
  for_each = var.agents

  name        = "${var.name_prefix}-${each.key}-state-bucket-${var.region}"
  description = "Allows the ${each.key} lifecycle worker to read and write OpenTofu state in the shared S3 bucket."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "StateBucketList"
        Effect = "Allow"
        Action = [
          "s3:GetBucketLocation",
          "s3:GetBucketVersioning",
          "s3:ListBucket",
        ]
        Resource = local.state_bucket_arn
      },
      {
        Sid    = "StateBucketObjectReadWrite"
        Effect = "Allow"
        Action = [
          "s3:AbortMultipartUpload",
          "s3:DeleteObject",
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
        ]
        Resource = "${local.state_bucket_arn}/*"
      },
      local.state_bucket_kms_statement,
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lifecycle_worker_state_bucket" {
  for_each   = var.agents
  role       = local.agent_role_names[each.key]
  policy_arn = aws_iam_policy.lifecycle_worker_state_bucket[each.key].arn
}

# ----------------------------------------------------------------
# Policy: RDS provisioning — describe + create
#
# Create actions carry security-enforcing conditions:
#   - ManageMasterUserPassword: master password stored in Secrets Manager
#     automatically (no plaintext credentials in state).
#   - PubliclyAccessible: instances must remain VPC-private.
#   - ManagedBy + Vpc request tags: resources must be tagged at creation
#     so subsequent mutating-action conditions can scope to them.
# StorageEncrypted and DatabaseEngine are enforced via IAM condition keys on
# create actions where AWS supports them (db* and cluster* resource types).
# ----------------------------------------------------------------
resource "aws_iam_policy" "lifecycle_worker_rds_provisioning" {
  for_each = var.agents

  name        = "${var.name_prefix}-${each.key}-rds-provisioning-${var.region}"
  description = "Allows the ${each.key} lifecycle worker to describe and provision RDS/Aurora instances and clusters."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RdsDescribe"
        Effect = "Allow"
        Action = [
          "rds:DescribeDBClusterParameterGroups",
          "rds:DescribeDBClusterParameters",
          "rds:DescribeDBClusterSnapshots",
          "rds:DescribeDBClusters",
          "rds:DescribeDBEngineVersions",
          "rds:DescribeDBInstances",
          "rds:DescribeDBParameterGroups",
          "rds:DescribeDBParameters",
          "rds:DescribeDBSnapshots",
          "rds:DescribeDBSubnetGroups",
          "rds:DescribeGlobalClusters",
          "rds:DescribePendingMaintenanceActions",
          "rds:ListTagsForResource",
        ]
        Resource = "*"
      },
      {
        Sid      = "CreateRdsServiceLinkedRole"
        Effect   = "Allow"
        Action   = "iam:CreateServiceLinkedRole"
        Resource = "*"
        Condition = {
          StringEquals = {
            "iam:AWSServiceName" = "rds.amazonaws.com"
          }
        }
      },
      {
        # Standalone RDS (non-Aurora) instance creates. Discriminated from
        # RdsCreateAuroraClusterInstance by rds:ManageMasterUserPassword = true,
        # which is absent on Aurora cluster member creates (password is managed
        # at the cluster level). Engine pinned to postgres; storage encryption
        # and public access enforced at create time.
        Sid    = "RdsCreateDbInstance"
        Effect = "Allow"
        Action = "rds:CreateDBInstance"
        Resource = [
          local.rds_resources.db,
          local.rds_resources.subgrp,
          local.rds_resources.pg_all,
        ]
        Condition = {
          Bool = {
            "rds:ManageMasterUserPassword" = "true"
            "rds:PubliclyAccessible"       = "false"
            "rds:StorageEncrypted"         = "true"
          }
          StringEquals = {
            "aws:RequestTag/ManagedBy" = local.managed_by_tag
            "aws:RequestTag/Vpc"       = each.value.vpc_id
            "rds:DatabaseEngine"       = "postgres"
          }
        }
      },
      {
        Sid    = "RdsCreateAuroraCluster"
        Effect = "Allow"
        Action = "rds:CreateDBCluster"
        Resource = [
          local.rds_resources.cluster,
          local.rds_resources.cluster_pg_all,
          local.rds_resources.subgrp,
        ]
        Condition = {
          Bool = {
            "rds:ManageMasterUserPassword" = "true"
            "rds:StorageEncrypted"         = "true"
          }
          StringEquals = {
            "aws:RequestTag/ManagedBy" = local.managed_by_tag
            "aws:RequestTag/Vpc"       = each.value.vpc_id
            "rds:DatabaseEngine"       = "aurora-postgresql"
          }
        }
      },
      {
        Sid    = "RdsCreateAuroraClusterInstance"
        Effect = "Allow"
        Action = "rds:CreateDBInstance"
        Resource = [
          local.rds_resources.cluster,
          local.rds_resources.db,
          local.rds_resources.pg_all,
          local.rds_resources.subgrp,
        ]
        Condition = {
          Bool = {
            "rds:PubliclyAccessible" = "false"
          }
          StringEquals = {
            "aws:RequestTag/ManagedBy" = local.managed_by_tag
            "aws:RequestTag/Vpc"       = each.value.vpc_id
            "rds:DatabaseEngine"       = "aurora-postgresql"
          }
        }
      },
      {
        Sid    = "RdsCreateParameterGroups"
        Effect = "Allow"
        Action = [
          "rds:CreateDBClusterParameterGroup",
          "rds:CreateDBParameterGroup",
        ]
        Resource = [
          local.rds_resources.cluster_pg,
          local.rds_resources.pg_sb,
        ]
        Condition = {
          StringEquals = {
            "aws:RequestTag/ManagedBy" = local.managed_by_tag
            "aws:RequestTag/Vpc"       = each.value.vpc_id
          }
        }
      },
      {
        Sid      = "RdsCreateDbSubnetGroup"
        Effect   = "Allow"
        Action   = "rds:CreateDBSubnetGroup"
        Resource = local.rds_resources.subgrp
        Condition = {
          StringEquals = {
            "aws:RequestTag/ManagedBy" = local.managed_by_tag
            "aws:RequestTag/Vpc"       = each.value.vpc_id
          }
        }
      },
      {
        Sid    = "RdsTagOnCreate"
        Effect = "Allow"
        Action = "rds:AddTagsToResource"
        Resource = [
          local.rds_resources.cluster,
          local.rds_resources.cluster_pg,
          local.rds_resources.db,
          local.rds_resources.pg_sb,
          local.rds_resources.subgrp,
        ]
        Condition = {
          StringEquals = {
            "aws:RequestTag/ManagedBy" = local.managed_by_tag
            "aws:RequestTag/Vpc"       = each.value.vpc_id
          }
        }
      },
      {
        Sid    = "RdsTagAppSnapshotOnCreate"
        Effect = "Allow"
        Action = "rds:AddTagsToResource"
        Resource = [
          local.rds_resources.cluster_snapshot,
          local.rds_resources.snapshot,
        ]
        Condition = {
          StringEqualsIfExists = {
            "aws:RequestTag/ManagedBy" = local.managed_by_tag
            "aws:RequestTag/Vpc"       = each.value.vpc_id
          }
        }
      },
      {
        Sid    = "RdsEncryptedStorageKmsViaRds"
        Effect = "Allow"
        Action = [
          "kms:CreateGrant",
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:GenerateDataKey",
        ]
        Resource = "*"
        Condition = {
          "ForAnyValue:StringEquals" = {
            "aws:CalledVia" = "rds.amazonaws.com"
          }
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lifecycle_worker_rds_provisioning" {
  for_each   = var.agents
  role       = local.agent_role_names[each.key]
  policy_arn = aws_iam_policy.lifecycle_worker_rds_provisioning[each.key].arn
}

# ----------------------------------------------------------------
# Policy: RDS mutation — modify, delete, snapshots, tag management
# ----------------------------------------------------------------
resource "aws_iam_policy" "lifecycle_worker_rds_mutation" {
  for_each = var.agents

  name        = "${var.name_prefix}-${each.key}-rds-mutation-${var.region}"
  description = "Allows the ${each.key} lifecycle worker to modify, delete, snapshot, and tag RDS/Aurora resources it owns."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RdsMutate"
        Effect = "Allow"
        Action = [
          "rds:DeleteDBCluster",
          "rds:DeleteDBClusterParameterGroup",
          "rds:DeleteDBInstance",
          "rds:DeleteDBParameterGroup",
          "rds:DeleteDBSubnetGroup",
          "rds:ModifyDBCluster",
          "rds:ModifyDBClusterParameterGroup",
          "rds:ModifyDBInstance",
          "rds:ModifyDBParameterGroup",
          "rds:ModifyDBSubnetGroup",
          "rds:RebootDBCluster",
          "rds:RebootDBInstance",
          "rds:ResetDBClusterParameterGroup",
          "rds:ResetDBParameterGroup",
        ]
        Resource = [
          local.rds_resources.cluster,
          local.rds_resources.cluster_pg,
          local.rds_resources.db,
          local.rds_resources.pg_sb,
          local.rds_resources.pg_all,
          local.rds_resources.subgrp,
        ]
        Condition = {
          BoolIfExists = {
            "rds:ManageMasterUserPassword" = "true"
          }
          StringEquals = {
            "aws:ResourceTag/ManagedBy" = local.managed_by_tag
            "aws:ResourceTag/Vpc"       = each.value.vpc_id
          }
        }
      },
      {
        Sid      = "RdsDeleteAuroraClusterFinalSnapshot"
        Effect   = "Allow"
        Action   = "rds:DeleteDBCluster"
        Resource = local.rds_resources.cluster_snapshot
        Condition = {
          StringEqualsIfExists = {
            "aws:RequestTag/ManagedBy" = local.managed_by_tag
            "aws:RequestTag/Vpc"       = each.value.vpc_id
          }
        }
      },
      {
        Sid      = "RdsCreateSnapshotFromManagedCluster"
        Effect   = "Allow"
        Action   = "rds:CreateDBClusterSnapshot"
        Resource = local.rds_resources.cluster
        Condition = {
          StringEquals = {
            "aws:ResourceTag/ManagedBy" = local.managed_by_tag
            "aws:ResourceTag/Vpc"       = each.value.vpc_id
          }
        }
      },
      {
        Sid      = "RdsCreateAppClusterSnapshot"
        Effect   = "Allow"
        Action   = "rds:CreateDBClusterSnapshot"
        Resource = local.rds_resources.cluster_snapshot
        Condition = {
          StringEqualsIfExists = {
            "aws:RequestTag/ManagedBy" = local.managed_by_tag
            "aws:RequestTag/Vpc"       = each.value.vpc_id
          }
        }
      },
      {
        Sid      = "RdsCreateSnapshotFromManagedInstance"
        Effect   = "Allow"
        Action   = "rds:CreateDBSnapshot"
        Resource = local.rds_resources.db
        Condition = {
          StringEquals = {
            "aws:ResourceTag/ManagedBy" = local.managed_by_tag
            "aws:ResourceTag/Vpc"       = each.value.vpc_id
          }
        }
      },
      {
        Sid      = "RdsCreateAppSnapshot"
        Effect   = "Allow"
        Action   = "rds:CreateDBSnapshot"
        Resource = local.rds_resources.snapshot
        Condition = {
          StringEqualsIfExists = {
            "aws:RequestTag/ManagedBy" = local.managed_by_tag
            "aws:RequestTag/Vpc"       = each.value.vpc_id
          }
        }
      },
      {
        Sid    = "RdsAddTagsToManagedResources"
        Effect = "Allow"
        Action = "rds:AddTagsToResource"
        Resource = [
          local.rds_resources.cluster,
          local.rds_resources.cluster_pg,
          local.rds_resources.cluster_snapshot,
          local.rds_resources.db,
          local.rds_resources.pg_sb,
          local.rds_resources.pg_all,
          local.rds_resources.snapshot,
          local.rds_resources.subgrp,
        ]
        Condition = {
          StringEquals = {
            "aws:ResourceTag/ManagedBy" = local.managed_by_tag
            "aws:ResourceTag/Vpc"       = each.value.vpc_id
          }
          StringEqualsIfExists = {
            "aws:RequestTag/ManagedBy" = local.managed_by_tag
            "aws:RequestTag/Vpc"       = each.value.vpc_id
          }
        }
      },
      {
        Sid    = "RdsRemoveTagsExceptScopingTags"
        Effect = "Allow"
        Action = "rds:RemoveTagsFromResource"
        Resource = [
          local.rds_resources.cluster,
          local.rds_resources.cluster_pg,
          local.rds_resources.cluster_snapshot,
          local.rds_resources.db,
          local.rds_resources.pg_sb,
          local.rds_resources.pg_all,
          local.rds_resources.snapshot,
          local.rds_resources.subgrp,
        ]
        Condition = {
          StringEquals = {
            "aws:ResourceTag/ManagedBy" = local.managed_by_tag
            "aws:ResourceTag/Vpc"       = each.value.vpc_id
          }
          "ForAllValues:StringNotEquals" = {
            "aws:TagKeys" = ["ManagedBy", "Vpc"]
          }
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lifecycle_worker_rds_mutation" {
  for_each   = var.agents
  role       = local.agent_role_names[each.key]
  policy_arn = aws_iam_policy.lifecycle_worker_rds_mutation[each.key].arn
}

# ----------------------------------------------------------------
# Policy: EC2 networking — VPC describe + security group management
# ----------------------------------------------------------------
resource "aws_iam_policy" "lifecycle_worker_ec2_provisioning" {
  for_each = var.agents

  name        = "${var.name_prefix}-${each.key}-ec2-provisioning-${var.region}"
  description = "Allows the ${each.key} lifecycle worker to describe VPCs and manage security groups it created."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Sid    = "Ec2VpcDescribe"
          Effect = "Allow"
          Action = [
            "ec2:DescribeAccountAttributes",
            "ec2:DescribeAvailabilityZones",
            "ec2:DescribeNetworkInterfaces",
            "ec2:DescribeRouteTables",
            "ec2:DescribeSecurityGroupRules",
            "ec2:DescribeSecurityGroups",
            "ec2:DescribeSubnets",
            "ec2:DescribeTags",
            "ec2:DescribeVpcAttribute",
            "ec2:DescribeVpcs",
          ]
          Resource = "*"
        },
        {
          Sid      = "Ec2CreateSecurityGroupResource"
          Effect   = "Allow"
          Action   = ["ec2:CreateSecurityGroup"]
          Resource = "${local.ec2_prefix}:security-group/*"
          Condition = {
            StringEquals = {
              "aws:RequestTag/ManagedBy" = local.managed_by_tag
              "aws:RequestTag/Vpc"       = each.value.vpc_id
            }
          }
        },
        {
          Sid    = "Ec2SecurityGroupMutate"
          Effect = "Allow"
          Action = [
            "ec2:AuthorizeSecurityGroupEgress",
            "ec2:AuthorizeSecurityGroupIngress",
            "ec2:DeleteSecurityGroup",
            "ec2:ModifySecurityGroupRules",
            "ec2:RevokeSecurityGroupEgress",
            "ec2:RevokeSecurityGroupIngress",
          ]
          Resource = "*"
          Condition = {
            StringEquals = {
              "aws:ResourceTag/ManagedBy" = local.managed_by_tag
              "aws:ResourceTag/Vpc"       = each.value.vpc_id
            }
          }
        },
        {
          Sid    = "Ec2CreateTagsOnCreateSecurityGroup"
          Effect = "Allow"
          Action = ["ec2:CreateTags"]
          Resource = [
            "${local.ec2_prefix}:security-group/*",
            "${local.ec2_prefix}:security-group-rule/*",
          ]
          Condition = {
            StringEquals = {
              "aws:RequestTag/ManagedBy" = local.managed_by_tag
              "aws:RequestTag/Vpc"       = each.value.vpc_id
              "ec2:CreateAction"         = "CreateSecurityGroup"
            }
          }
        },
        {
          Sid    = "Ec2CreateTagsOnManagedResources"
          Effect = "Allow"
          Action = ["ec2:CreateTags"]
          Resource = [
            "${local.ec2_prefix}:security-group/*",
            "${local.ec2_prefix}:security-group-rule/*",
          ]
          Condition = {
            StringEquals = {
              "aws:ResourceTag/ManagedBy" = local.managed_by_tag
              "aws:ResourceTag/Vpc"       = each.value.vpc_id
            }
            StringEqualsIfExists = {
              "aws:RequestTag/ManagedBy" = local.managed_by_tag
              "aws:RequestTag/Vpc"       = each.value.vpc_id
            }
          }
        },
        {
          Sid    = "Ec2DeleteTagsExceptScopingTags"
          Effect = "Allow"
          Action = ["ec2:DeleteTags"]
          Resource = [
            "${local.ec2_prefix}:security-group/*",
            "${local.ec2_prefix}:security-group-rule/*",
          ]
          Condition = {
            StringEquals = {
              "aws:ResourceTag/ManagedBy" = local.managed_by_tag
              "aws:ResourceTag/Vpc"       = each.value.vpc_id
            }
            "ForAllValues:StringNotEquals" = {
              "aws:TagKeys" = ["ManagedBy", "Vpc"]
            }
          }
        },
      ],
      local.agent_ec2_create_sg_vpc_statements[each.key]
    )
  })
}

resource "aws_iam_role_policy_attachment" "lifecycle_worker_ec2_provisioning" {
  for_each   = var.agents
  role       = local.agent_role_names[each.key]
  policy_arn = aws_iam_policy.lifecycle_worker_ec2_provisioning[each.key].arn
}

# ----------------------------------------------------------------
# Policy: Secrets Manager
# ----------------------------------------------------------------
resource "aws_iam_policy" "lifecycle_worker_secrets" {
  for_each = var.agents

  name        = "${var.name_prefix}-${each.key}-secrets-${var.region}"
  description = "Allows the ${each.key} lifecycle worker to manage RDS master credentials and read RDS-managed secrets."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CreateRdsManagedMasterSecrets"
        Effect = "Allow"
        Action = "secretsmanager:CreateSecret"
        Resource = [
          "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:rds!cluster-*",
          "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:rds!db-*",
        ]
        Condition = {
          "ForAnyValue:StringEquals" = {
            "aws:CalledVia" = "rds.amazonaws.com"
          }
          StringEquals = {
            "aws:RequestTag/ManagedBy" = local.managed_by_tag
            "aws:RequestTag/Vpc"       = each.value.vpc_id
          }
        }
      },
      {
        Sid    = "TagRdsManagedMasterSecretsViaRds"
        Effect = "Allow"
        Action = "secretsmanager:TagResource"
        Resource = [
          "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:rds!cluster-*",
          "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:rds!db-*",
        ]
        Condition = {
          "ForAnyValue:StringEquals" = {
            "aws:CalledVia" = "rds.amazonaws.com"
          }
          StringEquals = {
            "aws:RequestTag/ManagedBy" = local.managed_by_tag
            "aws:RequestTag/Vpc"       = each.value.vpc_id
          }
        }
      },
      {
        Sid      = "DescribeRdsManagedSecretKmsKeyViaRds"
        Effect   = "Allow"
        Action   = "kms:DescribeKey"
        Resource = "*"
        Condition = {
          "ForAnyValue:StringEquals" = {
            "aws:CalledVia" = "rds.amazonaws.com"
          }
        }
      },
      {
        Sid    = "ReadTaggedRdsManagedMasterSecrets"
        Effect = "Allow"
        Action = [
          "secretsmanager:DescribeSecret",
          "secretsmanager:GetSecretValue",
        ]
        Resource = [
          "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:rds!cluster-*",
          "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:rds!db-*",
        ]
        Condition = {
          StringEquals = {
            "aws:ResourceTag/ManagedBy" = local.managed_by_tag
            "aws:ResourceTag/Vpc"       = each.value.vpc_id
          }
        }
      },
      local.agent_rds_secret_kms_statements[each.key],
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lifecycle_worker_secrets" {
  for_each   = var.agents
  role       = local.agent_role_names[each.key]
  policy_arn = aws_iam_policy.lifecycle_worker_secrets[each.key].arn
}

# ----------------------------------------------------------------
# Policy: Observability (CloudWatch log groups + Enhanced Monitoring PassRole)
#
# The physical modules declare CloudWatch log groups explicitly so retention
# is managed rather than left unbounded, and they attach the shared
# monitoring role below. AWS requires whoever enables Enhanced Monitoring to
# hold iam:PassRole on the role being handed to RDS, so that grant is scoped
# to the single role and conditioned on the one service allowed to receive it.
# ----------------------------------------------------------------
resource "aws_iam_policy" "lifecycle_worker_observability" {
  for_each = var.agents

  name        = "${var.name_prefix}-${each.key}-observability-${var.region}"
  description = "Allows the ${each.key} lifecycle worker to manage App Database CloudWatch log groups and pass the shared Enhanced Monitoring role."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchLogGroupsForAppDatabases"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:DeleteLogGroup",
          "logs:ListTagsForResource",
          "logs:PutRetentionPolicy",
          "logs:TagResource",
          "logs:UntagResource",
        ]
        Resource = local.app_db_cloudwatch_log_group_arn_patterns
      },
      # The provider reads aws_cloudwatch_log_group through DescribeLogGroups,
      # which AWS authorizes only against "*" — an iam:SimulateCustomPolicy run
      # denies it against every log-group ARN pattern. Listing it beside the
      # scoped actions above silently loses the permission at refresh time.
      {
        Sid      = "DescribeLogGroupsIsNotResourceScopable"
        Effect   = "Allow"
        Action   = "logs:DescribeLogGroups"
        Resource = "*"
      },
      # CreateDBInstance passes the monitoring role as rds.amazonaws.com, not as
      # the monitoring.rds.amazonaws.com principal that assumes it. Conditioning
      # on the latter denies every physical provision once monitoring_interval
      # is non-zero: AWS reports "no identity-based policy allows the
      # iam:PassRole action" even though the statement's resource matches.
      {
        Sid      = "PassEnhancedMonitoringRole"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = local.monitoring_role_arn
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "rds.amazonaws.com"
          }
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lifecycle_worker_observability" {
  for_each   = var.agents
  role       = local.agent_role_names[each.key]
  policy_arn = aws_iam_policy.lifecycle_worker_observability[each.key].arn
}

####################################################################
# Enhanced Monitoring IAM Role (one per account, shared by all agents)
#
# RDS assumes this role to publish Enhanced Monitoring OS metrics to the
# RDSOSMetrics log group. The physical modules never create it: the attached
# AWS-managed policy is identical for every database, so one account-level
# role is reused by all of them and the worker never needs iam:CreateRole.
# The ArnLike/SourceAccount pair is confused-deputy protection — without it
# any RDS database in any account could name this role.
#
# IAM role names are account-global, so this name cannot repeat within one
# account: a second region (or a second install) must pass
# existing_monitoring_role_arn instead of letting the module create its own,
# or CreateRole fails with EntityAlreadyExists.
####################################################################
resource "aws_iam_role" "enhanced_monitoring" {
  count = local.create_monitoring_role ? 1 : 0

  name = "${var.name_prefix}-enhanced-monitoring"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowRdsEnhancedMonitoringForLifecycleDatabases"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
        Action = "sts:AssumeRole"
        Condition = {
          ArnLike = {
            "aws:SourceArn" = local.app_db_rds_monitoring_source_arn_patterns
          }
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })

  description = "RDS Enhanced Monitoring role shared by every app-database instance and cluster"

  tags = merge(local.tags, {
    Purpose = "RDS Enhanced Monitoring for app databases"
  })
}

resource "aws_iam_role_policy_attachment" "enhanced_monitoring" {
  count = local.create_monitoring_role ? 1 : 0

  role       = aws_iam_role.enhanced_monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

####################################################################
# Connector IAM Role (one per agent)
#
# Assumed at query time by the OPA serving code to generate an RDS IAM
# authentication token. Trusts only that agent's lifecycle worker role(s).
#
# Policy contains one rds-db:connect statement per data tag, scoping access to
# DB users in the sbndb_{profile_token}_*_runtime namespace. The lifecycle
# worker derives that token from the tag rather than using the tag itself, so a
# grant written against the bare tag matches no DB user and every query fails
# with AccessDenied.
#
# Role name format: superblocks-app-db-connector-{agent_name}
# "superblocks-app-db-connector" is a reserved prefix: the Superblocks
# server rejects customer-provided role names starting with it.
####################################################################
resource "aws_iam_role" "connector" {
  for_each = var.agents

  name = "superblocks-app-db-connector-${each.key}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowOnlyTrustedOpa"
        Effect    = "Allow"
        Action    = "sts:AssumeRole"
        Principal = { AWS = [local.agent_role_arns[each.key]] }
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_policy" "connector" {
  for_each = var.agents

  name        = "superblocks-app-db-connector-${each.key}"
  description = "Allows the ${each.key} connector role to authenticate to RDS/Aurora instances using IAM database authentication."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      for tag in each.value.agent_tags : {
        Sid    = "ConnectTag${replace(replace(title(tag), "-", ""), "_", "")}"
        Effect = "Allow"
        Action = "rds-db:connect"
        Resource = [
          "arn:aws:rds-db:${var.region}:${data.aws_caller_identity.current.account_id}:dbuser:cluster-*/sbndb_${local.profile_tokens[tag]}_*_runtime",
          "arn:aws:rds-db:${var.region}:${data.aws_caller_identity.current.account_id}:dbuser:db-*/sbndb_${local.profile_tokens[tag]}_*_runtime",
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "connector" {
  for_each   = var.agents
  role       = aws_iam_role.connector[each.key].name
  policy_arn = aws_iam_policy.connector[each.key].arn
}

####################################################################
# S3 OpenTofu State Bucket
#
# Shared across all agents in this module invocation (same account+region).
# Always created — no conditional logic needed since all agents are declared
# in this single module call.
#
# Bucket name format: <name_prefix>-<region>-<account_id>
####################################################################
resource "aws_s3_bucket" "tofu_state" {
  bucket = "${var.name_prefix}-${var.region}-${data.aws_caller_identity.current.account_id}"

  tags = local.tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "tofu_state" {
  bucket = aws_s3_bucket.tofu_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "tofu_state" {
  bucket = aws_s3_bucket.tofu_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tofu_state" {
  count  = var.kms_key_arn != null ? 1 : 0
  bucket = aws_s3_bucket.tofu_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = false
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "tofu_state" {
  bucket = aws_s3_bucket.tofu_state.id

  rule {
    id     = "expire-noncurrent-state-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}
