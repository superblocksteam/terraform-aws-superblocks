# EKS agents authenticate the lifecycle worker with either IRSA (an OIDC
# provider trust) or EKS Pod Identity. Pod Identity session tags are
# transitive and the connector trust does not allow sts:TagSession, so the
# association must disable them or every connector assume is denied.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_resource "aws_iam_policy" {
    defaults = {
      arn = "arn:aws:iam::123456789012:policy/mock"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/mock"
    }
  }
}

variables {
  allowed_origins = ["https://app.superblocks.com"]
  deployment_type = "eks"
  region          = "us-east-1"

  agents = {
    pod = {
      agent_tags                = ["production"]
      vpc_id                    = "vpc-0123456789abcdef0"
      namespace                 = "dataplane"
      service_account_name      = "pod-app-db-lifecycle"
      pod_identity_cluster_name = "example-dp-1"
    }
    irsa = {
      agent_tags        = ["staging"]
      vpc_id            = "vpc-0123456789abcdef0"
      oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE1234567890"
    }
  }
}

run "pod_identity_agent_trusts_eks_pods_only" {
  command = plan

  assert {
    condition = jsondecode(aws_iam_role.lifecycle_worker["pod"].assume_role_policy).Statement == [{
      Effect    = "Allow"
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Principal = { Service = "pods.eks.amazonaws.com" }
    }]
    error_message = "A Pod Identity agent's lifecycle worker must trust only pods.eks.amazonaws.com, with no OIDC federation."
  }

  assert {
    condition     = jsondecode(aws_iam_role.lifecycle_worker["irsa"].assume_role_policy).Statement[0].Action == "sts:AssumeRoleWithWebIdentity"
    error_message = "An agent without pod_identity_cluster_name must keep its IRSA trust."
  }
}

run "pod_identity_association_disables_session_tags" {
  command = plan

  assert {
    condition     = keys(aws_eks_pod_identity_association.lifecycle_worker) == ["pod"]
    error_message = "Only agents with pod_identity_cluster_name get a pod identity association."
  }

  assert {
    condition = (
      aws_eks_pod_identity_association.lifecycle_worker["pod"].cluster_name == "example-dp-1" &&
      aws_eks_pod_identity_association.lifecycle_worker["pod"].namespace == "dataplane" &&
      aws_eks_pod_identity_association.lifecycle_worker["pod"].service_account == "pod-app-db-lifecycle"
    )
    error_message = "The association must bind the agent's own cluster, namespace, and service account."
  }

  assert {
    condition     = aws_eks_pod_identity_association.lifecycle_worker["pod"].disable_session_tags == true
    error_message = "Transitive Pod Identity session tags would make the connector AssumeRole require sts:TagSession."
  }
}

# Both set: pods keep their IRSA session until they restart onto Pod Identity.
run "migrating_agent_trusts_both" {
  command = plan

  variables {
    agents = {
      both = {
        agent_tags                = ["production"]
        vpc_id                    = "vpc-0123456789abcdef0"
        oidc_provider_arn         = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE1234567890"
        pod_identity_cluster_name = "example-dp-1"
      }
    }
  }

  assert {
    condition = [
      for s in jsondecode(aws_iam_role.lifecycle_worker["both"].assume_role_policy).Statement :
      try(s.Principal.Service, s.Principal.Federated)
      ] == [
      "pods.eks.amazonaws.com",
      "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE1234567890",
    ]
    error_message = "An agent with both settings must trust Pod Identity and its IRSA provider."
  }

  assert {
    condition     = keys(aws_eks_pod_identity_association.lifecycle_worker) == ["both"]
    error_message = "A migrating agent still gets its pod identity association."
  }
}

run "eks_agent_needs_an_identity" {
  command = plan

  variables {
    agents = {
      none = {
        agent_tags = ["production"]
        vpc_id     = "vpc-0123456789abcdef0"
      }
    }
  }

  expect_failures = [aws_iam_role.lifecycle_worker]
}

run "pod_identity_requires_eks" {
  command = plan

  variables {
    deployment_type = "fargate"
    agents = {
      pod = {
        agent_tags                = ["production"]
        vpc_id                    = "vpc-0123456789abcdef0"
        pod_identity_cluster_name = "example-dp-1"
      }
    }
  }

  expect_failures = [aws_eks_pod_identity_association.lifecycle_worker]
}
