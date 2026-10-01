# Changelog

## Unreleased

### App DB prereqs: optional permissions boundary on created roles

`app-db-prereqs` takes an optional `permissions_boundary` (an IAM managed policy
ARN, default `null`). When set, it is attached at creation to every role the
module creates: each lifecycle worker role, each connector role, and the
Enhanced Monitoring role. Roles supplied through `existing_role_name` or
`existing_monitoring_role_arn` are left unchanged. With the default, nothing
changes and existing deployments plan no diff.

This is for accounts that require new roles to carry a named boundary, where
`iam:CreateRole` is denied for any role created without it. Two constraints
apply. The boundary caps each role to the intersection of its policies and the
boundary, so it must allow everything the module grants (`sts:AssumeRole` on the
connector, `rds-db:connect`, and the lifecycle worker's RDS, EC2, Secrets
Manager, KMS, S3, CloudWatch Logs, `iam:CreateServiceLinkedRole` and
`iam:PassRole` statements). Otherwise the roles create cleanly and then fail at
runtime with AccessDenied. And such boundaries usually also deny
`iam:PutRolePermissionsBoundary`, so set the value before the roles are first
created and treat it as permanent.

### App DB prereqs: artifacts bucket, CORS, and worker grants

`app-db-prereqs` provisions `<s3_artifacts_name_prefix>-<region>-<account-id>`
beside the OpenTofu state bucket, with `prevent_destroy` and no versioning.
A bucket policy denies requests that are not HTTPS. When explicit HTTPS
`allowed_origins` are supplied, CORS exposes `ETag` for
multipart uploads. Completed objects do not expire: the orchestrator deletes
objects it is done with. A seven-day S3 lifecycle safety net only aborts
incomplete multipart uploads and their orphaned parts.

A dedicated artifacts IAM policy is attached only to each lifecycle-worker
role so connector roles remain limited to `rds-db:connect`. The worker can
sign uploads, read and delete objects under each profile token, and use
`kms:Decrypt`, `kms:DescribeKey`, and `kms:GenerateDataKey` when
`artifacts_kms_key_arn` is set. SSE-KMS on that bucket enables a bucket
key so multipart uploads do not call KMS once per part. Pass
`artifacts_bucket_name` and `agents[].artifacts_key_prefix` into a top-level
Helm `artifacts` block (`bucket` and `keyPrefix`), not `databaseLifecycle`.

One bucket is shared by every agent pointed at it.
`agents[].artifacts_key_prefix` is an optional namespace (empty by default)
passed through as Helm `artifacts.keyPrefix` when more than one agent
shares the bucket. Object keys are
`<keyPrefix>/<profileToken>/<kind>/...` (no `keyPrefix` segment when unset).
IAM is `[<keyPrefix>/]<profileToken>/*`, so exports and later kinds need no
re-apply.

The new `s3_artifacts_name_prefix` defaults to `sb-data-artifacts` and caps at
20 characters. Like `s3_name_prefix` for state, it identifies the bucket
owned by one module invocation. Independent invocations in the same account
and region must use distinct prefixes; separate Terraform states must not
manage the same bucket. Both bucket names freeze independently via
`prevent_destroy`. `terraform destroy` will refuse to delete either bucket;
the artifacts bucket may still contain customer objects. To retire them,
empty the artifacts bucket and delete both buckets outside Terraform, or
remove the two bucket resources from state if you are abandoning them.
Callers whose deployer can only create buckets under a
specific name prefix must set `s3_artifacts_name_prefix` to a matching value
before the first apply. Setting `allowed_origins` also requires the deployer
to have `s3:PutBucketCORS` on the artifacts bucket. The HTTPS-only bucket
policy requires `s3:PutBucketPolicy`.

The existing `kms_key_arn` continues to configure the OpenTofu state bucket.
The new `artifacts_kms_key_arn` independently configures customer data so a
principal that can decrypt state cannot decrypt artifacts.

### App DB: Helm physicalModuleTags is inventory only

The EKS example no longer passes ownership keys through `physicalModuleTags`.
Requires Helm chart 2.69.1+ and packaged physical modules v0.4.10.

### App DB: pool.min_available_capacity_percent

Default 20, rendered as `physicalDatabase.minAvailableCapacityPercent`.

### App DB prereqs: authorize tagged security-group rule creation

Lifecycle workers can authorize new ingress and egress rule resources when
their create request carries the required agent, lifecycle, and VPC tags.
Canonical ownership and APN tag values are enforced when supplied. Existing
security-group mutation remains scoped by resource tags.

## v1.5.2

### App DB: ownership and APN tags

`app-db-prereqs` and `app-db` always stamp `superblocks:owned=true` and
`aws-apn-id=pc:ctelqp437y3cvjkv5rv0z2w4f` on resources they create; lifecycle-worker
IAM protects those keys from removal.
([#66](https://github.com/superblocksteam/terraform-aws-superblocks/pull/66))

### App DB prereqs: independent IAM / S3 name prefixes

`name_prefix` is replaced by `iam_name_prefix` and `s3_name_prefix` (both default
`sb-app-db`). Callers that set `name_prefix` must switch to the two new variables.
([#67](https://github.com/superblocksteam/terraform-aws-superblocks/pull/67))

### App DB prereqs: create-time tags on security-group rules

Create-time `ec2:CreateTags` authorization now covers security-group rule creates
(`AuthorizeSecurityGroupIngress` / `Egress`) in addition to `CreateSecurityGroup`.
([#68](https://github.com/superblocksteam/terraform-aws-superblocks/pull/68))
