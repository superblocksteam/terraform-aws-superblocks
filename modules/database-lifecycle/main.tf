resource "aws_s3_bucket" "lifecycle_state" {
  bucket = local.state_bucket_name

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-db-lifecycle-state"
  })
}

resource "aws_s3_bucket_public_access_block" "lifecycle_state" {
  bucket = aws_s3_bucket.lifecycle_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "lifecycle_state" {
  bucket = aws_s3_bucket.lifecycle_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "lifecycle_state" {
  bucket = aws_s3_bucket.lifecycle_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_dynamodb_table" "terraform_locks" {
  name         = local.lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-db-lifecycle-locks"
  })
}

data "aws_iam_policy_document" "database_lifecycle_task" {
  statement {
    sid    = "LifecycleTerraformState"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = [
      aws_s3_bucket.lifecycle_state.arn,
      "${aws_s3_bucket.lifecycle_state.arn}/*",
    ]
  }

  statement {
    sid    = "LifecycleTerraformLocks"
    effect = "Allow"
    actions = [
      "dynamodb:DescribeTable",
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem",
    ]
    resources = [aws_dynamodb_table.terraform_locks.arn]
  }

  statement {
    sid    = "LifecycleDatabaseCredentials"
    effect = "Allow"
    actions = [
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue",
    ]
    resources = ["${var.secrets_manager_allowed_prefix}*"]
  }

  statement {
    sid    = "LifecycleRDSCreate"
    effect = "Allow"
    actions = [
      "ec2:DescribeSubnets",
      "ec2:DescribeVpcs",
      "rds:AddTagsToResource",
      "rds:CreateDBInstance",
      "rds:CreateDBSubnetGroup",
      "rds:DeleteDBInstance",
      "rds:DeleteDBSubnetGroup",
      "rds:DescribeDBInstances",
      "rds:DescribeDBSubnetGroups",
      "rds:ListTagsForResource",
      "rds:ModifyDBInstance",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "database_lifecycle_task" {
  name_prefix = "${var.name_prefix}-db-lifecycle-"
  policy      = data.aws_iam_policy_document.database_lifecycle_task.json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "database_lifecycle_task" {
  count = var.task_role_arn != null ? 1 : 0

  role       = element(split("/", var.task_role_arn), length(split("/", var.task_role_arn)) - 1)
  policy_arn = aws_iam_policy.database_lifecycle_task.arn
}
