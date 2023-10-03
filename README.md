<h1 align="center">
  <img src="https://raw.githubusercontent.com/superblocksteam/terraform-aws-superblocks/main/assets/logo.png" style="height:60px"/>
</h1>

<h1 align="center">Superblocks Terraform Module - AWS</h1>

<br/>

This document contains configuration and deployment details for deploying the Superblocks agent to AWS.

## Deploy with Terraform

### Install Terraform

To install Terraform on MacOS

```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
```

Terraform officially supports `MacOS|Windows|Linux|FreeBSD|OpenBSD|Solaris`
Check out this <https://developer.hashicorp.com/terraform/downloads> for more details

### Deploy Superblocks On-Premise-Agent

#### Create your Terraform file

To get started, you'll need a `superblocks_agent_key`. To generate an agent key, go to the [Superblocks On-Premise Agent Setup Wizard](https://app.superblocks.com/opas)

```terraform
module "terraform_aws_superblocks" {
  source  = "superblocksteam/superblocks/aws"
  version = ">=0.1.0"

  vpc_id         = "[VPC_ID]"
  lb_subnet_ids  = "[LIST_OF_SUBNET_IDS_FOR_LOAD_BALANCER]"
  ecs_subnet_ids = "[LIST_OF_SUBNET_IDS_FOR_SUPERBLOCKS_AGENT_ECS_CLUSTER]"
  domain         = "[DOMAIN]"
  subdomain      = "[SUBDOMAIN_FOR_SUPERBLOCKS_AGENT]"

  superblocks_agent_key = "[SUPERBLOCKS_AGENT_KEY]"
}
```

If you are in the **[EU region](https://eu.superblocks.com)**, ensure that

```terraform
superblocks_agent_data_domain = "eu.superblocks.com"
```

is set in your configuration in the module block.

To find your VPC use `aws ec2 describe-vpcs` or by finding them in the AWS management console.

#### Deploy

```bash
terraform init
terraform apply
```

### Advanced Configuration

#### Public Networking

ECS instances running the Superblocks On-Premise Agent are configured to receive traffic from a **private** Elastic Load Balancer. Allow public traffic to your On-Premise Agent by adding

```terraform
lb_internal = false
```

#### VPC

The module by default deploys the OPA within an existing VPC. If you want your agent to access data across multiple VPCs, you can update the module to **create a new VPC** then set up VPC peering between the newly configured VPC and existing AWS VPCs. To update the module to create a new VPC

```terraform
create_vpc = true
```

For more details on configuring VPC peering see [Connect VPCs using VPC peering](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-peering.html).

#### Security Group

A default security group will be created with an ingress cidr blocks `0.0.0.0/0`. To use your own security group

```terraform
create_sg = false
security_group_ids = "<LIST_OF_YOUR_SECURITY_GROUP_IDS>"
```

#### Load Balancer

A new Elastic Load Balancer will be created by default to handle TLS termination before sending traffic to your ECS instances. To use an existing Loading Balancer, update the module to include

```terraform
create_lb = false
lb_target_group_arn = "<YOUR_TARGET_GROUP_ARN>"
```

To find your target ground ARN use `aws elbv2 describe-target-groups` or by finding the Load Balancer in the AWS management console.

#### DNS & Certificate

If you use Route53 for domain management you can use the Terraform module to generate a DNS record and  certificate for your agent, and associated both with your Load Balancer. If you don't use Route53 or want to use an existing certificate & DNS record, add the following to your configuration

```terraform
create_certs = false
create_dns = false
certificate_arn = "<YOUR_CERTIFICATE_ARN>"
```

To find the certificate's ARN use `aws acm list-certificates` or by finding the Certificate in the AWS management console. For additional instructions on creating a certificate manually see [Issue and manage certificates](https://docs.aws.amazon.com/acm/latest/userguide/gs.html).

#### Instance Sized

Configure the CPU & memory limits allocated to your ECS instances use

```terraform
container_cpu = 1024
container_memory = 4096
```

#### Scaling

AWS will automatically scale your ECS instances based on traffic. To configure the minimum and maximum number of instances the agent can scale to, set

```terraform
container_min_capacity = 1
container_max_capacity = 10
```

#### Security Groups

By default, security groups will be created for both the loadbalancer and ECS cluster.
You can modify the default security ECS group rules with the following variables:

```terraform
variable "load_balancer_sg_ids" {
  type        = list(string)
  default     = []
  description = "Specify loadbalancer security group ids to allow traffic from. Only used when create_ecs_sg is set to true."
}

variable "ecs_sg_egress_with_cidr_blocks" {
  type = list(map(string))
  default = [
    {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      description = "All egress traffic"
      cidr_blocks = "0.0.0.0/0"
    }
  ]
  description = "Specify egress rules for the ECS cluster. Only used if create_ecs_sg is set to true."
}
```

You can modify the default loadbalancer security group rules with the following variables:

```terraform
variable "lb_sg_ingress_with_cidr_blocks" {
  type = list(map(string))
  default = [
    {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      description = "HTTPS"
      cidr_blocks = "0.0.0.0/0"
    }
  ]
  description = "Specify ingress rules for the load balancer. Only used if create_lb_sg is set to true."
}

variable "lb_sg_egress_with_cidr_blocks" {
  type = list(map(string))
  default = [
    {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      description = "All Egress"
      cidr_blocks = "0.0.0.0/0"
    }
  ]
  description = "Specify egress rules for the load balancer. Only used if create_lb_sg is set to true."
}
```

To disable default security groups, you can set

```terraform
create_lb_sg = false
create_ecs_sg = false
```

You may specify your own security groups to be assigned to the loadbalancer and the ECS cluster using the following variables:

```terraform
variable "lb_security_group_ids" {
  type        = list(string)
  default     = []
  description = "Specify additional security groups to associate with the load balancer. This will be joined with the default security group if created."
}

variable "ecs_security_group_ids" {
  type        = list(string)
  default     = []
  description = "Specify additional security groups to associate with the ECS cluster. This will be joined with the default security group if created."
}
```

#### Other Configurable Options

```terraform
variable "superblocks_agent_tags" {
  type        = string
  default     = "profile:*"
  description = <<EOF
    Use this variable to specify which profile-specific workloads can be executed on this agent.
    It accepts a comma (and colon) separated string representing key-value pairs, and currently only the "profile" key is used.

    Some examples:
    - To support all API executions:      "profile:*"
    - To support staging and production:  "profile:staging,profile:production"
    - To support only staging:            "profile:staging"
    - To support only production:         "profile:production"
    - To support a custom profile:        "profile:custom_profile_key"
  EOF
}

variable "superblocks_agent_image" {
  type        = string
  default     = "ghcr.io/superblocksteam/agent"
  description = "The docker image used by Superblocks Agent container instance"
}

variable "superblocks_agent_role_arn" {
  type        = string
  default     = null
  description = "ARN of IAM role that allows the Superblocks Agent container(s) to make calls to other AWS services. This can be leveraged for using Superblocks integrations like S3, DynamoDB, etc."
}

variable "name_prefix" {
  type        = string
  default     = "superblocks"
  description = "This will be prepended to the name of each AWS resource created by this module"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "A series of tags that will be added to each AWS resource created by this module"
}

variable "superblocks_grpc_msg_res_max" {
  type        = string
  default     = "100000000"
  description = "The maximum message size in bytes allowed to be sent by the gRPC server. This is used to prevent malicious clients from sending large messages to cause memory exhaustion."
}

variable "superblocks_grpc_msg_req_max" {
  type        = string
  default     = "30000000"
  description = "The maximum message size in bytes allowed to be received by the gRPC server. This is used to prevent malicious clients from sending large messages to cause memory exhaustion."
}

variable "superblocks_timeout" {
  type        = string
  default     = "10000000000"
  description = "The maximum amount of time in nanoseconds before a request is aborted. This applies for http requests against the Superblocks server and does not apply to the execution time limit of a workload."
}

variable "superblocks_log_level" {
  type        = string
  default     = "info"
  description = "Logging level for the superblocks agent. Accepted values are 'debug', 'info', 'warn', 'error', 'fatal', 'panic'."
}

variable "superblocks_agent_handle_cors" {
  type        = bool
  default     = true
  description = "Whether to enable CORS support for the Superblocks Agent. This is required if you don't have a reverse proxy in front of the agent that handles CORS. This will allow CORS for all origins."
}

variable "superblocks_agent_environment_variables" {
  type        = list(map(string))
  default     = []
  description = "Environment variables that will be passed to the Superblocks Agent container(s). This can be specified in the form of [{name = "key", value = "value"}]."
}
```

## Migration Guides

### 0.x to 1.x

* `deploy_in_ecs` variable has been completely removed.
* `create_sg` variable replaced by two new variables:
  * `create_lb_sg` creates a default loadbalancer security group.
  * `create_ecs_sg` creates a default loadbalancer security group.
* `security_group_ids` variable replaced by two new variables:
  * `lb_security_group_ids` allows users to set security groups for the loadbalancer, if `create_lb` is set to true.
  * `ecs_security_group_ids` allows users to set security groups for the ECS cluster.
* `create_dns` no longer creates both certificate and the DNS entry. A new `create_certs` flag exists to create create the ACM certificate. `create_dns` now only determines whether the DNS entry to point to the loadbalancer is created.
