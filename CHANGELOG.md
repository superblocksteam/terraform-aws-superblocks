# Changelog

## Unreleased

### App DB prereqs: artifacts object access, signature version, and state encryption

When the artifacts bucket exists, its policy now denies object actions
(`s3:GetObject`, `s3:PutObject`, `s3:DeleteObject`, `s3:AbortMultipartUpload`,
`s3:ListMultipartUploadParts`) unless `aws:PrincipalArn` is a lifecycle worker
role or an ARN in `artifacts_object_access_exempt_principal_arns`. That
includes roles passed as `existing_role_name`. `restrict_artifacts_object_access`
defaults to `true`. The exempt list defaults to empty. The deny also blocks
the account root. To break glass, add that role ARN to the exempt list, apply,
then remove it. Bucket-level actions stay allowed, so the deploy role can
still manage CORS, lifecycle, and the bucket policy. Presigned browser uploads
are evaluated as the worker that signed them. An identity policy that allows
object writes, including a name-scoped `S3BucketMutate` grant, does not
override this bucket deny.

The same policy always denies requests whose `s3:signatureversion` is not
`AWS4-HMAC-SHA256`. A request that omits the signature version is denied,
because `StringNotEquals` matches a missing key. Presigned uploads and other
SigV4 requests send the version.

When `artifacts_kms_key_arn` is set, `PutObject` is denied when the encryption
algorithm header is present and is not `aws:kms`, and denied again when the
KMS key id header is present and is not that full key ARN. The data plane must
send that ARN. A key ID or an alias does not match. Each check requires the
header to be present (`Null` = false) before comparing it. `UploadPart` cannot
send those headers. Encryption is set on `CreateMultipartUpload`, and a missing
header is not denied. `StringNotEqualsIfExists` would deny the missing header.
Without a KMS key, those denies are absent and the bucket stays SSE-S3.

There is no input for arbitrary extra policy statements, and no VPC-endpoint
list. A browser import upload does not come from the customer's VPC endpoint,
so denying object actions that lack `aws:SourceVpce` would reject the upload.
A caller statement that reused a module Sid would replace that statement,
including the object-access deny, and no customer statement is waiting on that
input.

`artifacts_kms_key_arn` and `artifacts_server_side_encryption_algorithm` are
outputs. They are null when the bucket is not created. Randall marked the
encryption outputs optional; they are included so a caller can pass the
algorithm and key into the data plane without repeating the input.

The OpenTofu state bucket now always declares encryption, still at
`aws_s3_bucket_server_side_encryption_configuration.tofu_state[0]`. No `moved`
block: the address does not change. SSE-S3 (`AES256`) when `kms_key_arn` is
null, SSE-KMS with a bucket key when it is set, and SSE-C is blocked either
way. A deployment that already set `kms_key_arn` will plan
`bucket_key_enabled` from `false` to `true` and add the SSE-C block. A
deployment that never set a key gains the encryption configuration. The KMS
IAM statement is still attached only when `kms_key_arn` is set.

### App DB: the data plane must be able to reach its clusters

`app-db` fails the plan when `physical_module_inputs` sets neither
`source_security_group_ids` nor `allowed_cidr_blocks`, matching the Helm
chart. Each cluster admits port 5432 only from those two lists, so a caller
that set neither got clusters the OPA could not connect to. A `null` element
in either `source_security_group_ids` or `allowed_cidr_blocks` is rejected
too. For security groups, that is what the root module's
`ecs_security_group_id` output holds when `create_ecs_sg = false`. A null
CIDR is the same hole: the list is non-empty, so a length check would count
it. Callers who already pass one of the two lists see no change.

`examples/app-db-fargate` now wires `source_security_group_ids` from the root
module's `ecs_security_group_id` output. The pre-created group it used to call
for is not needed; a literal ID of the same group keeps working.

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

`app-db-prereqs` can provision `<s3_artifacts_name_prefix>-<region>-<account-id>`
beside the OpenTofu state bucket, with `prevent_destroy` and no versioning.
`create_artifacts_bucket` defaults to `false`. When it is false, the module
creates no artifacts bucket, public access block, bucket policy, encryption,
CORS, lifecycle rule, or lifecycle-worker artifacts policy, and
`artifacts_bucket_name` is null. Set it to `true` before the first apply that
should store imports and exports. A deployment that already created the bucket
must leave it `true`: `prevent_destroy` blocks a later apply from deleting it.
`moved` blocks keep an existing bucket, public access block, bucket policy, and
lifecycle rule when the variable stays true.

A bucket policy denies requests that are not HTTPS. `enable_public_access_blocks`
defaults to `true` and creates the public access block on the OpenTofu state
bucket and, when the artifacts bucket exists, on that bucket too. All four
flags are set. Set the variable to `false` only where an organization policy
denies `s3:PutBucketPublicAccessBlock` and the account already blocks public
access. A `moved` block keeps an existing state-bucket block at its new
address when the variable stays `true`, so that apply does not replace it.
Switching an existing deployment from `true` to `false` deletes the
bucket-level blocks. If that delete is denied, remove the blocks from state
before applying.

When the artifacts bucket exists it always has default encryption: SSE-KMS with
`artifacts_kms_key_arn` when that key is set, otherwise SSE-S3 (`AES256`).
SSE-C is blocked. That argument requires AWS provider 6.22.0 or later for every
caller of this module, including when the artifacts bucket is not created. CORS is
configured whenever the bucket exists and exposes `ETag` for multipart uploads.
An empty `allowed_origins` allows `https://<superblocks_agent_data_domain>`
(`app.superblocks.com` by default, or `eu.superblocks.com`). A non-empty
`allowed_origins` replaces that origin. Completed objects do not expire: the
orchestrator deletes objects it is done with. A seven-day S3 lifecycle safety
net only aborts incomplete multipart uploads and their orphaned parts.

When the bucket is created, a dedicated artifacts IAM policy is attached only
to each lifecycle-worker role so connector roles remain limited to
`rds-db:connect`. The worker can
sign uploads, read and delete objects under each profile token, and use
`kms:Decrypt`, `kms:DescribeKey`, and `kms:GenerateDataKey` when
`artifacts_kms_key_arn` is set. SSE-KMS on that bucket enables a bucket
key so multipart uploads do not call KMS once per part. Pass
`artifacts_bucket_name` and `agents[].artifacts_key_prefix` into a top-level
Helm `artifacts` block (`bucket` and `keyPrefix`), not `databaseLifecycle`.
On Fargate, pass those outputs to `modules/app-db` as `artifacts_bucket_name`
and `artifacts_key_prefix`, and pass `artifacts_kms_key_arn` when that key is
set. `ecs_env_vars` then includes `SUPERBLOCKS_ARTIFACTS_BUCKET` and
`SUPERBLOCKS_ARTIFACTS_REGION`, plus `SUPERBLOCKS_ARTIFACTS_KEY_PREFIX` and
`SUPERBLOCKS_ARTIFACTS_KMS_KEY_ARN` only when those values are set. A null
bucket name adds none of them.

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
`prevent_destroy`. `terraform destroy` will refuse to delete the state bucket,
and the artifacts bucket once it has been created. The artifacts bucket may
still contain customer objects. To retire them, empty the artifacts bucket and
delete both buckets outside Terraform, or remove the bucket resources from
state if you are abandoning them. Callers whose deployer can only create
buckets under a specific name prefix must set `s3_artifacts_name_prefix` to a
matching value before the first apply. Creating the artifacts bucket requires
`s3:PutBucketCORS`, `s3:PutBucketPolicy`, and `s3:PutEncryptionConfiguration`,
and `s3:PutBucketPublicAccessBlock` unless `enable_public_access_blocks` is false.

`kms_key_arn` still selects encryption for the OpenTofu state bucket only.
That configuration is now always declared; see the state-bucket encryption
note above. `artifacts_kms_key_arn` independently configures customer data so
a principal that can decrypt state cannot decrypt artifacts.

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
