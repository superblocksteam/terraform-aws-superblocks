locals {
  policies = concat([aws_iam_policy.superblocks_agent_policy.arn], var.additional_ecs_execution_task_policy_arns)
  ecs_container_definition = {
    name      = "superblocks-agent"
    image     = var.container_image
    cpu       = var.container_cpu
    memory    = var.container_memory
    essential = true
    repositoryCredentials = var.repository_credentials_secret_arn != null ? {
      credentialsParameter = var.repository_credentials_secret_arn
    } : null
    portMappings = [
      {
        containerPort = var.container_port_http
        hostPort      = var.container_port_http
      },
      {
        containerPort = var.container_port_grpc
        hostPort      = var.container_port_grpc
      }
    ],
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-create-group  = "true"
        awslogs-group         = "/superblocks-agent"
        awslogs-region        = var.region
        awslogs-stream-prefix = "superblocks-agent"
      }
    }
    environment = var.container_environment
  }
}

resource "aws_ecs_cluster" "superblocks" {
  name = "${var.name_prefix}-cluster"
  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = var.tags
}

resource "aws_ecs_cluster_capacity_providers" "superblocks" {
  cluster_name       = aws_ecs_cluster.superblocks.name
  capacity_providers = var.ecs_cluster_capacity_providers
}

resource "aws_ecs_service" "superblocks" {
  name            = "${var.name_prefix}-service"
  cluster         = aws_ecs_cluster.superblocks.id
  task_definition = aws_ecs_task_definition.superblocks_agent.arn
  desired_count   = var.container_min_capacity
  launch_type     = "FARGATE"

  dynamic "load_balancer" {
    for_each = var.target_group_http_arns
    content {
      target_group_arn = load_balancer.value
      container_name   = "superblocks-agent"
      container_port   = var.container_port_http
    }
  }

  dynamic "load_balancer" {
    for_each = var.target_group_grpc_arns
    content {
      target_group_arn = load_balancer.value
      container_name   = "superblocks-agent"
      container_port   = var.container_port_grpc
    }
  }

  network_configuration {
    subnets         = var.subnet_ids
    security_groups = var.create_sg ? concat([module.ecs_security_group[0].security_group_id], var.security_group_ids) : var.security_group_ids
  }

  tags = var.tags
}

resource "aws_ecs_task_definition" "superblocks_agent" {
  family                   = "${var.name_prefix}-superblocks-agent"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.container_cpu
  memory                   = var.container_memory
  execution_role_arn       = aws_iam_role.superblocks_agent_role.arn
  task_role_arn            = var.task_role_arn

  container_definitions = jsonencode(
    [
      {
        for k, v in local.ecs_container_definition : k => v if v != null
      }
    ]
  )
  tags = var.tags
}

####################################################################
# ECS Task Execution Role
####################################################################
resource "aws_iam_role" "superblocks_agent_role" {
  name_prefix        = "${var.name_prefix}-agent-role"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF

  tags = var.tags
}

resource "aws_iam_policy" "superblocks_agent_policy" {
  name_prefix = "${var.name_prefix}-agent-policy"
  policy      = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "superblocks_agent_policy_attachment" {
  count      = length(local.policies)
  role       = aws_iam_role.superblocks_agent_role.name
  policy_arn = local.policies[count.index]
}

####################################################################
# Auto Scaling
####################################################################
resource "aws_appautoscaling_target" "superblocks" {
  max_capacity       = var.container_max_capacity
  min_capacity       = var.container_min_capacity
  resource_id        = "service/${aws_ecs_cluster.superblocks.name}/${aws_ecs_service.superblocks.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "memory" {
  name               = "${var.name_prefix}-scaling-policy-memory"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.superblocks.resource_id
  scalable_dimension = aws_appautoscaling_target.superblocks.scalable_dimension
  service_namespace  = aws_appautoscaling_target.superblocks.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }

    target_value = var.container_scale_up_when_memory_pct_above
  }
}

resource "aws_appautoscaling_policy" "cpu" {
  name               = "${var.name_prefix}-scaling-policy-cpu"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.superblocks.resource_id
  scalable_dimension = aws_appautoscaling_target.superblocks.scalable_dimension
  service_namespace  = aws_appautoscaling_target.superblocks.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }

    target_value = var.container_scale_up_when_cpu_pct_above
  }
}

module "ecs_security_group" {
  count   = var.create_sg ? 1 : 0
  source  = "terraform-aws-modules/security-group/aws"
  version = ">=5.0.0"
  name    = "${var.name_prefix}-ecs-sg"
  vpc_id  = var.vpc_id
  ingress_with_source_security_group_id = flatten([
    for sg_id in var.load_balancer_sg_ids : [
      {
        from_port                = var.container_port_http
        to_port                  = var.container_port_http
        protocol                 = "tcp"
        description              = "Ingress from load balancer"
        source_security_group_id = sg_id
      },
      {
        from_port                = var.container_port_grpc
        to_port                  = var.container_port_grpc
        protocol                 = "tcp"
        description              = "Ingress from load balancer"
        source_security_group_id = sg_id
      }
    ]
  ])
  egress_with_cidr_blocks = var.sg_egress_with_cidr_blocks
  tags                    = var.tags
  use_name_prefix         = true
}
