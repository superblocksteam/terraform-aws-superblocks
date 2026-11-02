# Changelog

## Unreleased

### Breaking: App DB requires OPA v1.53.0 unless verify_infra_absence_enabled = false

`app-db` now renders the `verify_database_infra_absence` operation (backend
`native_runner`) by default, matching the Helm chart. Without it a Fargate OPA
never advertised the operation, so marking a database deleted after a failed
retirement was refused with "No active owning App Database agent supports
infrastructure absence verification".

OPA images before v1.53.0 exit at startup when the operation is present. The
root module now fails the plan when the lifecycle config includes it and
`superblocks_agent_image` is tagged below v1.53.0. Digests, `latest`, and other
tags that are not a version are not checked. To upgrade gradually, set
`verify_infra_absence_enabled = false` on `app-db`, upgrade the image, then
remove the override. `examples/app-db-fargate` now pins `v1.53.0`.

The root module now requires Terraform or OpenTofu 1.2 or later, for the plan
check above.

`app-db` also sets `SUPERBLOCKS_DATABASE_LIFECYCLE_DISPATCH_WATCH_ENABLED=true`,
the Helm default. The worker leaves the watch off when the variable is unset,
so Fargate OPAs polled every 30 seconds for work that EKS OPAs claimed at once.
Images before v1.51.0 ignore the variable and keep polling.

## v1.6.0

### App DB prereqs: artifacts object access, signature version, and state encryption

When the artifacts bucket exists, object actions are denied unless the
principal is a lifecycle worker role, including `existing_role_name`, or an
ARN in `artifacts_object_access_exempt_principal_arns`. Presigned uploads are
evaluated as the worker that signed them. Requests that are not SigV4 are
denied. When `artifacts_kms_key_arn` is set, a present encryption header must
name `aws:kms` and that full key ARN; a missing header is not denied. The
state bucket always encrypts: SSE-S3 when `kms_key_arn` is unset, SSE-KMS with
a bucket key when it is set, and SSE-C is blocked. An existing key plans
`bucket_key_enabled` from `false` to `true`.
([#82](https://github.com/superblocksteam/terraform-aws-superblocks/pull/82))

### App DB: the data plane must be able to reach its clusters

`app-db` fails the plan when neither `source_security_group_ids` nor
`allowed_cidr_blocks` is set, and when either list contains null. Callers who
already pass one list see no change.
([#78](https://github.com/superblocksteam/terraform-aws-superblocks/pull/78))

### App DB prereqs: optional permissions boundary on created roles

Optional `permissions_boundary` is attached at creation to each lifecycle
worker, connector, and Enhanced Monitoring role this module creates. Roles
passed in through `existing_role_name` or `existing_monitoring_role_arn` are
unchanged. The default plans no diff. Set the boundary before those roles are
first created, and make sure it allows the actions they use.
([#79](https://github.com/superblocksteam/terraform-aws-superblocks/pull/79))

### App DB prereqs: artifacts bucket, CORS, and worker grants

`create_artifacts_bucket` defaults to `false`. When it is `true`, the module
creates `<s3_artifacts_name_prefix>-<region>-<account-id>` (default prefix
`sb-data-artifacts`) with HTTPS-only access, default encryption, CORS, and a
lifecycle-worker policy. The name freezes after the first apply. A deployer
that can only create buckets under a given prefix must set
`s3_artifacts_name_prefix` before that apply. This module requires AWS
provider 6.22.0 or later even when the bucket stays off. Pass the bucket name
and optional key prefix to Fargate or to the top-level Helm `artifacts` block.
([#76](https://github.com/superblocksteam/terraform-aws-superblocks/pull/76), [#80](https://github.com/superblocksteam/terraform-aws-superblocks/pull/80))

### App DB: Helm physicalModuleTags is inventory only

The EKS example no longer passes ownership keys through `physicalModuleTags`.
Requires Helm chart 2.69.1+ and packaged physical modules v0.4.10.
([#73](https://github.com/superblocksteam/terraform-aws-superblocks/pull/73))

### App DB: pool.min_available_capacity_percent

The default is 20, rendered as `physicalDatabase.minAvailableCapacityPercent`.
([#72](https://github.com/superblocksteam/terraform-aws-superblocks/pull/72))

## v1.5.3

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
