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

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = "superblocks-agent"
    container_port   = var.container_port
  }

  network_configuration {
    subnets         = var.subnet_ids
    security_groups = var.security_group_ids
  }

  tags = var.tags
}

resource "aws_ecs_task_definition" "superblocks_agent" {
  family                   = "superblocks-agent"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.container_cpu
  memory                   = var.container_memory
  execution_role_arn       = aws_iam_role.superblocks_agent_role.arn
  container_definitions    = <<DEFINITION
  [
    {
      "name": "superblocks-agent",
      "image": "${var.container_image}",
      "cpu": ${var.container_cpu},
      "memory": ${var.container_memory},
      "essential": true,
      "portMappings": [
        {
          "containerPort": ${var.container_port},
          "hostPort": ${var.container_port}
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-create-group": "true",
          "awslogs-group": "/superblocks-agent",
          "awslogs-region": "${var.region}",
          "awslogs-stream-prefix": "superblocks-agent"
        }
      },
      "environment": ${var.container_environment}
    }
  ]
  DEFINITION

  tags = var.tags
}

####################################################################
# ECS Task Role
####################################################################
resource "aws_iam_role" "superblocks_agent_role" {
  name               = "${var.name_prefix}-agent-role"
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
  name   = "${var.name_prefix}-agent-policy"
  policy = <<EOF
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

resource "aws_iam_role_policy_attachment" "policy-attach" {
  role       = aws_iam_role.superblocks_agent_role.name
  policy_arn = aws_iam_policy.superblocks_agent_policy.arn
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
  name               = "scaling-policy-memory"
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
  name               = "scaling-policy-cpu"
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
