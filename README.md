<p align="center">
  <img src="./assets/logo.png" height="60"/>
</p>

<h1 align="center">Superblocks Terraform Module - AWS</h1>

<br/>

This document contains configuration and deployment details for deploying the Superblocks agent to AWS.

## Deploy with Terraform

### Install Terraform

To install Terraform on MacOS
```
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
```

Terraform officially supports `MacOS|Windows|Linux|FreeBSD|OpenBSD|Solaris`
Check out this https://developer.hashicorp.com/terraform/downloads for more details

### Deploy Superblocks On-Premise-Agent

#### Create your Terraform file
```
module "terraform-aws-superblocks" {
  source  = "superblocks/terraform-aws-superblocks"
  version = ">=1.0"
}
```

#### Deploy
```
terraform init
terraform apply
```
