# Changelog

## Unreleased

### Root module: upgrading from a pre-1.0 deployment no longer fails with a cycle

v1.0.0 renamed `modules/dns` to `modules/certs` and removed the `count` from the
ECS module without recording either as a state move, so upgrading read both as
destroy/create. The ACM certificate cannot be destroyed while the ALB listener
references it, which Terraform reports as `Error: Cycle:` rather than a plan.
`moved` blocks now cover that rename, the ECS `count` removal, and two later
renames (`aws_lb_target_group.superblocks` to `.http` in v1.3.2, and
`aws_iam_role_policy_attachment.policy-attach` to
`.superblocks_agent_policy_attachment[0]` in v1.2.0 -- the replacement is
counted, so that move names an index). Upgrading now requires
Terraform 1.1 or later, which is where `moved` blocks were introduced.
([#17](https://github.com/superblocksteam/terraform-aws-superblocks/issues/17))

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
