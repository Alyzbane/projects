module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.7.2"

  name = local.name
  cidr = var.vpc_cidr

  azs             = var.availability_zones
  public_subnets  = ["10.42.0.0/20", "10.42.16.0/20"]
  private_subnets = ["10.42.128.0/20", "10.42.144.0/20"]

  enable_nat_gateway = false
  enable_vpn_gateway = false

  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = local.name
  }
}

module "alb_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "6.0.0"

  name        = "${local.name}-alb"
  description = "ALB security group"
  vpc_id      = module.vpc.vpc_id

  ingress_rules = {
    http = {
      from_port   = 80
      to_port     = 80
      ip_protocol = "tcp"
      cidr_ipv4   = "0.0.0.0/0"
      description = "HTTP from internet"
    }
  }

  egress_rules = {
    all = {
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
      description = "All outbound"
    }
  }
}

module "ecs_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "6.0.0"

  name        = "${local.name}-ecs"
  description = "ECS task security group"
  vpc_id      = module.vpc.vpc_id

  ingress_rules = {
    paperless = {
      from_port                    = 8000
      to_port                      = 8000
      ip_protocol                  = "tcp"
      referenced_security_group_id = module.alb_sg.id
      description                  = "Paperless from ALB"
    }
  }

  egress_rules = {
    all = {
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
      description = "All outbound"
    }
  }
}

module "rds_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "6.0.0"

  name        = "${local.name}-rds"
  description = "RDS security group"
  vpc_id      = module.vpc.vpc_id

  ingress_rules = {
    postgres = {
      from_port                    = 5432
      to_port                      = 5432
      ip_protocol                  = "tcp"
      referenced_security_group_id = module.ecs_sg.id
      description                  = "PostgreSQL from ECS"
    }
  }
}

module "efs_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "6.0.0"

  name        = "${local.name}-efs"
  description = "EFS security group"
  vpc_id      = module.vpc.vpc_id

  ingress_rules = {
    nfs = {
      from_port                    = 2049
      to_port                      = 2049
      ip_protocol                  = "tcp"
      referenced_security_group_id = module.ecs_sg.id
      description                  = "NFS from ECS"
    }
  }
}

resource "aws_cloudwatch_log_group" "paperless" {
  name              = "/ecs/${local.name}"
  retention_in_days = 14
}

resource "aws_ecs_cluster" "paperless" {
  name = local.name
}

resource "aws_efs_file_system" "paperless" {
  encrypted = true

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }
}

resource "aws_efs_mount_target" "paperless" {
  for_each = zipmap(var.availability_zones, module.vpc.private_subnets)

  file_system_id  = aws_efs_file_system.paperless.id
  subnet_id       = each.value
  security_groups = [module.efs_sg.id]
}

resource "aws_efs_access_point" "data" {
  file_system_id = aws_efs_file_system.paperless.id

  root_directory {
    path = "/data"

    creation_info {
      owner_gid   = 1000
      owner_uid   = 1000
      permissions = "0775"
    }
  }
}

resource "aws_efs_access_point" "media" {
  file_system_id = aws_efs_file_system.paperless.id

  root_directory {
    path = "/media"

    creation_info {
      owner_gid   = 1000
      owner_uid   = 1000
      permissions = "0775"
    }
  }
}

resource "aws_efs_access_point" "consume" {
  file_system_id = aws_efs_file_system.paperless.id

  root_directory {
    path = "/consume"

    creation_info {
      owner_gid   = 1000
      owner_uid   = 1000
      permissions = "0775"
    }
  }
}

resource "aws_efs_access_point" "export" {
  file_system_id = aws_efs_file_system.paperless.id

  root_directory {
    path = "/export"

    creation_info {
      owner_gid   = 1000
      owner_uid   = 1000
      permissions = "0775"
    }
  }
}

module "db" {
  source  = "terraform-aws-modules/rds/aws"
  version = "7.2.1"

  identifier = "${local.name}-postgres"

  engine               = "postgres"
  engine_version       = "17"
  family               = "postgres17"
  major_engine_version = "17"
  instance_class       = var.database_instance_class

  allocated_storage     = var.database_allocated_storage
  max_allocated_storage = 50
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = "paperless"
  username = "paperless"

  manage_master_user_password = true
  port                        = 5432

  create_db_subnet_group = true
  subnet_ids             = module.vpc.private_subnets

  vpc_security_group_ids = [module.rds_sg.id]

  backup_retention_period = 1
  deletion_protection     = false
  skip_final_snapshot     = true
}

resource "random_password" "paperless_secret_key" {
  length  = 64
  special = true
}

resource "aws_secretsmanager_secret" "paperless_secret_key" {
  name                    = "${local.name}/paperless-secret-key"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "paperless_secret_key" {
  secret_id     = aws_secretsmanager_secret.paperless_secret_key.id
  secret_string = random_password.paperless_secret_key.result
}

resource "aws_iam_role" "ecs_execution" {
  name = "${local.name}-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs_execution_secrets" {
  name = "read-secrets"
  role = aws_iam_role.ecs_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["secretsmanager:GetSecretValue"]
      Resource = [
        module.db.db_instance_master_user_secret_arn,
        aws_secretsmanager_secret.paperless_secret_key.arn
      ]
    }]
  })
}

resource "aws_lb" "paperless" {
  name               = substr(replace(local.name, "_", "-"), 0, 32)
  internal           = false
  load_balancer_type = "application"
  security_groups    = [module.alb_sg.id]
  subnets            = module.vpc.public_subnets
}

resource "aws_lb_target_group" "paperless" {
  name        = substr("${local.name}-tg", 0, 32)
  port        = 8000
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = module.vpc.vpc_id

  health_check {
    enabled             = true
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 5
    timeout             = 10
    interval            = 30
    matcher             = "200-399"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.paperless.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.paperless.arn
  }
}

resource "aws_ecs_task_definition" "paperless" {
  family                   = local.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.ecs_cpu
  memory                   = var.ecs_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn

  container_definitions = jsonencode([
    {
      name      = "paperless"
      image     = var.paperless_image
      essential = true

      portMappings = [{
        containerPort = 8000
        hostPort      = 8000
        protocol      = "tcp"
      }]

      environment = [
        { name = "PAPERLESS_DBHOST", value = module.db.db_instance_address },
        { name = "PAPERLESS_DBPORT", value = "5432" },
        { name = "PAPERLESS_DBNAME", value = "paperless" },
        { name = "PAPERLESS_REDIS", value = "redis://127.0.0.1:6379" },
        { name = "PAPERLESS_TIME_ZONE", value = var.paperless_timezone },
        { name = "PAPERLESS_URL", value = local.paperless_url },
        { name = "PAPERLESS_CSRF_TRUSTED_ORIGINS", value = local.paperless_url }
      ]

      secrets = [
        {
          name      = "PAPERLESS_DBUSER"
          valueFrom = "${module.db.db_instance_master_user_secret_arn}:username::"
        },
        {
          name      = "PAPERLESS_DBPASS"
          valueFrom = "${module.db.db_instance_master_user_secret_arn}:password::"
        },
        {
          name      = "PAPERLESS_SECRET_KEY"
          valueFrom = aws_secretsmanager_secret.paperless_secret_key.arn
        }
      ]

      mountPoints = [
        {
          sourceVolume  = "data"
          containerPath = "/usr/src/paperless/data"
          readOnly      = false
        },
        {
          sourceVolume  = "media"
          containerPath = "/usr/src/paperless/media"
          readOnly      = false
        },
        {
          sourceVolume  = "consume"
          containerPath = "/usr/src/paperless/consume"
          readOnly      = false
        },
        {
          sourceVolume  = "export"
          containerPath = "/usr/src/paperless/export"
          readOnly      = false
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.paperless.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "paperless"
        }
      }
    },
    {
      name      = "valkey"
      image     = "docker.io/valkey/valkey:9-alpine"
      essential = true
      command   = ["valkey-server", "--appendonly", "no"]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.paperless.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "valkey"
        }
      }
    }
  ])

  volume {
    name = "data"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.paperless.id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.data.id
      }
    }
  }

  volume {
    name = "media"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.paperless.id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.media.id
      }
    }
  }

  volume {
    name = "consume"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.paperless.id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.consume.id
      }
    }
  }

  volume {
    name = "export"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.paperless.id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.export.id
      }
    }
  }
}

resource "aws_ecs_service" "paperless" {
  name            = local.name
  cluster         = aws_ecs_cluster.paperless.id
  task_definition = aws_ecs_task_definition.paperless.arn
  desired_count   = 1
  launch_type     = "FARGATE"


  network_configuration {
    subnets          = module.vpc.public_subnets
    security_groups  = [module.ecs_sg.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.paperless.arn
    container_name   = "paperless"
    container_port   = 8000
  }

  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  health_check_grace_period_seconds = 180

  depends_on = [
    aws_iam_role_policy.ecs_execution_secrets,
    aws_lb_listener.http,
    aws_efs_mount_target.paperless
  ]
}
