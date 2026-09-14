# AGENTS.md - Terraform AWS Superblocks

## Overview

Customer-facing Terraform module that deploys the Superblocks **On-Premise Agent (OPA)** on AWS. The agent runs on **ECS Fargate** behind an **Application Load Balancer**, with optional VPC creation, ACM certificate management, and Route53 DNS configuration. Published to the Terraform Registry as [`superblocksteam/superblocks/aws`](https://registry.terraform.io/modules/superblocksteam/superblocks/aws).

This module deploys the Docker image maintained in the `orchestrator`/`agent` repository.

## Engineering-Wide Context

For broader Superblocks standards (architecture, observability, incident workflow):

```bash
gh api repos/superblocksteam/engineering/contents/AGENTS.md --jq '.content' | base64 --decode
```

## Cross-Repo Sync

This repository is one of three parallel OPA deployment modules:

| Repository | Cloud | Compute |
|---|---|---|
| **terraform-aws-superblocks** (this repo) | AWS | ECS Fargate + ALB |
| `terraform-azure-superblocks` | Azure | Container Apps |
| `terraform-google-superblocks` | GCP | Cloud Run |

Changes to one should be accompanied by corresponding changes in the others where applicable (agent env vars, new features, documentation). See the engineering repo's `.cursor/rules/opa-terraform-modules.mdc` for details.

## Repository Structure

```
terraform-aws-superblocks/
├── main.tf              # Root module orchestrating all sub-modules
├── variables.tf         # Input variables
├── outputs.tf           # Module outputs
├── locals.tf            # Computed values
├── provider.tf          # Terraform/provider version constraints
├── moved.tf             # State moves for renames in past releases (see below)
├── modules/
│   ├── vpc/             # VPC, subnets, NAT gateways, internet gateway
│   ├── load-balancer/   # ALB, target groups, listeners, Route53 record
│   ├── ecs/             # ECS Fargate cluster, service, task definition, auto-scaling
│   ├── certs/           # ACM certificate with DNS validation
│   └── security-group/  # Reusable security group module
├── examples/
│   ├── complete/              # Full configuration
│   ├── simple-public-agent/   # Minimal public deployment
│   ├── simple-private-agent/  # Minimal private deployment
│   ├── custom-vpc/            # Using existing VPC
│   ├── custom-cert/           # Using existing certificate
│   └── external-and-internal-lbs/  # Dual LB setup
└── tests/
    ├── upgrade_from_pre_1.0.tftest.hcl  # Upgrades must move state, not replace it
    └── fixtures/pre-1.0/                # Seeds state at the old addresses
```

## Commands

```bash
terraform fmt -recursive   # Format all files
terraform validate         # Validate configuration
terraform plan             # Preview changes
terraform apply            # Apply changes

terraform test             # Run the .tftest.hcl suites (mocked AWS, no credentials)

pre-commit install         # One-time setup
pre-commit run --all-files # Run formatting hooks
```

Test suites live in `tests/` (root module) and `modules/<name>/tests/`. They all
use `mock_provider "aws"`, so they need no AWS account and create nothing.

`.github/workflows/terraform.yaml` validates every module and runs the suites on
each PR. Note that three runs in `modules/app-db-prereqs` currently fail on
`main`: they assert on `aws_iam_policy.*.policy`, which is unknown at plan time
on current Terraform. That directory is deliberately left out of the CI gate
rather than papered over, and belongs back in once those assertions are fixed.

## Module Architecture

The root module (`main.tf`) conditionally creates resources via sub-modules:

1. **VPC** (optional, `create_vpc = true`) -- VPC with public/private subnets, NAT gateways
2. **Certificates** (optional, `create_certs = true`) -- ACM certificate with DNS validation
3. **Load Balancer** (optional, `create_lb = true`) -- ALB with HTTP/gRPC target groups, HTTPS listener, Route53 CNAME
4. **ECS** (always) -- Fargate cluster, service, task definition, auto-scaling, CloudWatch logs

Each sub-module can be skipped by providing existing resources (VPC ID, certificate ARN, target group ARNs).

## Code Style

### File Naming

| File | Purpose |
|------|---------|
| `main.tf` | Primary resources |
| `variables.tf` | Input variables |
| `outputs.tf` / `output.tf` | Output values |
| `locals.tf` | Computed local values |
| `provider.tf` | Provider and Terraform version constraints |

### Variable Definitions

```hcl
variable "superblocks_agent_key" {
  type        = string
  sensitive   = true
  description = "Superblocks agent key"
}
```

### Resource Naming

- Use `name_prefix` variable (default: `"superblocks"`) for all resource names
- Merge custom tags with default tags via `var.tags`

## Key Variables

| Variable | Default | Description |
|---|---|---|
| `superblocks_agent_key` | (required) | Agent authentication key |
| `domain` | `""` | Domain for DNS/certs |
| `subdomain` | `"superblocks-agent"` | Subdomain prefix |
| `create_vpc` | `false` | Create new VPC |
| `create_lb` | `true` | Create ALB |
| `create_certs` | `true` | Create ACM certificate |
| `container_min_capacity` | `1` | Min ECS tasks |
| `container_max_capacity` | `5` | Max ECS tasks |
| `superblocks_agent_environment` | `"*"` | Agent environment tag |

## Provider Requirements

- Terraform: `>= 1.1` for the root module, `modules/ecs` and
  `modules/load-balancer` (they contain `moved` blocks); `>= 1.0` elsewhere
- AWS provider: `>= 5.0.0`

## Renaming Anything Is a Breaking Change

This module is consumed from the Terraform Registry, so its resource addresses
are part of its public API. A customer's state file holds
`module.<their_name>.module.certs[0].aws_acm_certificate.superblocks` -- rename
the submodule directory, rename a resource, or add or remove a `count`, and
Terraform sees the old address disappear and a new one appear. It plans a
destroy and a create, which for stateful resources means the customer loses
them.

For the ACM certificate the failure is worse than a replacement. The certificate
cannot be destroyed while the ALB listener references it, and the listener
cannot move to a new certificate until that one is validated, so Terraform
reports `Error: Cycle:` and refuses to produce a plan at all. That is issue
[#17](https://github.com/superblocksteam/terraform-aws-superblocks/issues/17),
which went unfixed from v1.0.0 through v1.5.3 because nothing in the repo tested
upgrades.

So, when you rename a module or a resource, or change its `count`/`for_each`:

1. Add a `moved` block in the same change -- `moved.tf` at the root, or
   `moved.tf` beside the resource inside a submodule. Never rename without one.
2. Keep it forever. `moved` blocks are a no-op for anyone who never had the old
   address, and deleting one silently breaks whoever has not upgraded yet.
3. Bump that module's `required_version` to at least `>= 1.1`.
4. Cover it with a test that fails without the `moved` block. The pattern:
   seed state at the old addresses from a fixture, apply the current module over
   that same state via a shared `state_key`, and assert resource ids are
   unchanged -- a replaced resource comes back with a fresh id under the mock
   provider. Root-module moves go in `tests/upgrade_from_pre_1.0.tftest.hcl`;
   a move inside a submodule goes in that module's own `tests/`, because a
   module-level run can reference its resources directly while the root suite
   can only see module outputs. Always verify the new assertion by deleting the
   `moved` block and watching it fail -- an assertion that cannot fail is how a
   missing instance index shipped once already.

   Watch the index mode in particular. If the replacement resource has `count`
   or `for_each` and the old one did not, the `moved` block must name an index
   (`to = aws_foo.bar[0]`). A whole-resource move preserves instance keys, so
   without it the old no-key instance lands on an address the config does not
   declare and Terraform silently plans destroy/create.
5. Document it under `## Migration Guides` in README.md, including anything
   `moved` cannot fix (replacements forced by `name` to `name_prefix` changes,
   resources that are genuinely deleted).

## Conventions

- Use **allowlist** / **denylist** (not whitelist/blacklist)
- Keep lists alphabetically ordered where order is not meaningful
- Never commit secrets or `.tfvars` files containing credentials
- Mark sensitive variables with `sensitive = true`
