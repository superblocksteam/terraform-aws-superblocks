# Changelog

## Unreleased

### Breaking / upgrade notes

#### App Database ownership and APN tags (`app-db`, `app-db-prereqs`)

`app-db-prereqs` and `app-db` now always stamp `superblocks:owned=true` and
`aws-apn-id=pc:ctelqp437y3cvjkv5rv0z2w4f` on resources they create (or render
into runtime physical-module inputs). The lifecycle worker IAM policies also
protect those keys from removal (and require the canonical values when the
worker writes them via tag APIs).

**Upgrade together.** Once `app-db-prereqs` protects the ownership keys, do not
pin `app-db` to an older release that omits them from `physical_module_inputs.tags`.
That skew fails closed on later physical applies: OpenTofu tries to remove the
tags, and `rds:RemoveTagsFromResource` / `ec2:DeleteTags` are denied.

Tags land on new creates and on the next apply that touches that state. There
is no automatic backfill of idle fleets.

`existing_role_name` still attaches policies to a customer-provided lifecycle
role; this module does **not** tag that existing role. Ownership tags apply to
resources this module creates (policies, connector/monitoring roles when
created, state bucket) and to runtime App DB resources via `app-db` / Helm
`physicalModuleTags`.
