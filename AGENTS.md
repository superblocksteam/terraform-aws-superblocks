# AGENTS.md - Terraform AWS Superblocks

## Overview

Customer-facing Terraform module that deploys the Superblocks **On-Premise Agent (OPA)** on AWS. The agent runs on **ECS Fargate** behind an **Application Load Balancer**, with optional VPC creation, ACM certificate management, and Route53 DNS configuration. Published to the Terraform Registry as [`superblocksteam/superblocks/aws`](https://registry.terraform.io/modules/superblocksteam/superblocks/aws).

This module deploys the same `orchestrator` Docker image used across all Superblocks agent deployments.

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
├── modules/
│   ├── vpc/             # VPC, subnets, NAT gateways, internet gateway
│   ├── load-balancer/   # ALB, target groups, listeners, Route53 record
│   ├── ecs/             # ECS Fargate cluster, service, task definition, auto-scaling
│   ├── certs/           # ACM certificate with DNS validation
│   └── security-group/  # Reusable security group module
└── examples/
    ├── complete/              # Full configuration
    ├── simple-public-agent/   # Minimal public deployment
    ├── simple-private-agent/  # Minimal private deployment
    ├── custom-vpc/            # Using existing VPC
    ├── custom-cert/           # Using existing certificate
    └── external-and-internal-lbs/  # Dual LB setup
```

## Commands

```bash
terraform fmt -recursive   # Format all files
terraform validate         # Validate configuration
terraform plan             # Preview changes
terraform apply            # Apply changes

pre-commit install         # One-time setup
pre-commit run --all-files # Run formatting hooks
```

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
| `subdomain` | `"agent"` | Subdomain prefix |
| `create_vpc` | `false` | Create new VPC |
| `create_lb` | `true` | Create ALB |
| `create_certs` | `true` | Create ACM certificate |
| `container_min_capacity` | `1` | Min ECS tasks |
| `container_max_capacity` | `1` | Max ECS tasks |
| `superblocks_agent_environment` | `"*"` | Agent environment tag |

## Provider Requirements

- Terraform: `>= 1.0`
- AWS provider: `>= 5.0.0`

## Conventions

- Use **allowlist** / **denylist** (not whitelist/blacklist)
- Keep lists alphabetically ordered where order is not meaningful
- Never commit secrets or `.tfvars` files containing credentials
- Mark sensitive variables with `sensitive = true`
