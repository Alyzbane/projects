################################################################################
# Availability zones and VPC
################################################################################

data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.7.2"

  name = local.name
  cidr = var.vpc_cidr

  azs             = slice(data.aws_availability_zones.available.names, 0, 2)
  public_subnets  = ["10.42.0.0/20", "10.42.16.0/20"]
  private_subnets = ["10.42.128.0/20", "10.42.144.0/20"]

  # One NAT Gateway provides outbound access for the private ECS subnets.
  # This is cheaper than one NAT Gateway per AZ, but less highly available.
  enable_nat_gateway = true
  single_nat_gateway = true
  enable_vpn_gateway = false

  enable_dns_hostnames = true
  enable_dns_support   = true
}

################################################################################
# DNS and ACM certificate
################################################################################

resource "aws_route53_zone" "this" {
  count = var.route53_zone_id == null ? 1 : 0
  name  = local.zone_name
}

resource "aws_acm_certificate" "paperless" {
  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "certificate_validation" {
  for_each = {
    for option in aws_acm_certificate.paperless.domain_validation_options : option.domain_name => {
      name   = option.resource_record_name
      record = option.resource_record_value
      type   = option.resource_record_type
    }
  }

  zone_id = local.zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.record]

  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "paperless" {
  certificate_arn         = aws_acm_certificate.paperless.arn
  validation_record_fqdns = [for record in aws_route53_record.certificate_validation : record.fqdn]
}

resource "aws_route53_record" "paperless" {
  zone_id = local.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = module.alb.dns_name
    zone_id                = module.alb.zone_id
    evaluate_target_health = true
  }
}

################################################################################
# Application Load Balancer
################################################################################

module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "10.5.1"

  name               = local.name
  load_balancer_type = "application"
  vpc_id             = module.vpc.vpc_id
  subnets            = module.vpc.public_subnets

  # Disabled for this demo so `make destroy` can remove the load balancer.
  enable_deletion_protection = false

  security_group_ingress_rules = {
    http = {
      from_port   = 80
      to_port     = 80
      ip_protocol = "tcp"
      cidr_ipv4   = "0.0.0.0/0"
    }
    https = {
      from_port   = 443
      to_port     = 443
      ip_protocol = "tcp"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }

  security_group_egress_rules = {
    ecs = {
      from_port                    = 8000
      to_port                      = 8000
      ip_protocol                  = "tcp"
      referenced_security_group_id = module.ecs_sg.id
    }
  }

  target_groups = {
    paperless = {
      name_prefix       = "pcl-"
      backend_protocol  = "HTTP"
      backend_port      = 8000
      target_type       = "ip"
      create_attachment = false

      health_check = {
        enabled             = true
        path                = "/"
        port                = "traffic-port"
        protocol            = "HTTP"
        matcher             = "200-399"
        healthy_threshold   = 2
        unhealthy_threshold = 5
        timeout             = 10
        interval            = 30
      }
    }
  }

  listeners = {
    http = {
      port     = 80
      protocol = "HTTP"
      redirect = {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
    https = {
      port            = 443
      protocol        = "HTTPS"
      certificate_arn = aws_acm_certificate_validation.paperless.certificate_arn

      forward = {
        target_group_key = "paperless"
      }

      # Protected paths are forwarded only for approved source CIDRs.
      rules = {
        admin-api-allowed = {
          priority = 10
          actions = [{
            forward = {
              target_group_key = "paperless"
            }
          }]
          conditions = [
            { path_pattern = { values = local.admin_protected_paths } },
            { source_ip = { values = var.admin_allowed_cidrs } }
          ]
        }

        admin-api-denied = {
          priority = 20
          actions = [{
            fixed_response = {
              status_code  = "403"
              content_type = "text/plain"
              message_body = "Access Denied"
            }
          }]
          conditions = [
            { path_pattern = { values = local.admin_protected_paths } }
          ]
        }
      }
    }
  }

  depends_on = [aws_acm_certificate_validation.paperless]
}

################################################################################
# Security groups
################################################################################

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
      referenced_security_group_id = module.alb.security_group_id
      description                  = "Paperless from ALB"
    }
  }

  egress_rules = {
    postgres = {
      from_port   = 5432
      to_port     = 5432
      ip_protocol = "tcp"
      cidr_ipv4   = var.vpc_cidr
      description = "PostgreSQL in the VPC"
    }
    efs = {
      from_port   = 2049
      to_port     = 2049
      ip_protocol = "tcp"
      cidr_ipv4   = var.vpc_cidr
      description = "EFS in the VPC"
    }
    dns_udp = {
      from_port   = 53
      to_port     = 53
      ip_protocol = "udp"
      cidr_ipv4   = var.vpc_cidr
      description = "VPC DNS resolver"
    }
    dns_tcp = {
      from_port   = 53
      to_port     = 53
      ip_protocol = "tcp"
      cidr_ipv4   = var.vpc_cidr
      description = "VPC DNS resolver"
    }
    https = {
      from_port   = 443
      to_port     = 443
      ip_protocol = "tcp"
      cidr_ipv4   = "0.0.0.0/0"
      description = "HTTPS for image pulls and external calls"
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

################################################################################
# ECS cluster, logging, and persistent storage
################################################################################

resource "aws_cloudwatch_log_group" "paperless" {
  name              = "/ecs/${local.name}"
  retention_in_days = 1
}

module "ecs_cluster" {
  source  = "terraform-aws-modules/ecs/aws"
  version = "7.6.0"

  cluster_name = local.name

  cluster_capacity_providers = ["FARGATE"]
  default_capacity_provider_strategy = {
    FARGATE = {
      weight = 100
    }
  }
}

resource "aws_efs_file_system" "paperless" {
  encrypted = true

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }
}

resource "aws_efs_mount_target" "paperless" {
  for_each = {
    for index, subnet_id in module.vpc.private_subnets : index => subnet_id
  }

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

################################################################################
# RDS PostgreSQL
################################################################################

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
  port     = 5432

  manage_master_user_password = true

  create_db_subnet_group = true
  subnet_ids             = module.vpc.private_subnets
  vpc_security_group_ids = [module.rds_sg.id]

  backup_retention_period = 1
  # Demo settings: destroy removes the database without a final snapshot.
  deletion_protection = false
  skip_final_snapshot = true
}

################################################################################
# Secrets
################################################################################

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

################################################################################
# ECS Fargate application service
################################################################################

module "ecs_service" {
  source  = "terraform-aws-modules/ecs/aws//modules/service"
  version = "7.6.0"

  name        = local.name
  cluster_arn = module.ecs_cluster.cluster_arn

  cpu    = var.ecs_cpu
  memory = var.ecs_memory

  launch_type   = "FARGATE"
  desired_count = 1

  # Keep the ECS task private 
  # the NAT Gateway provides outbound internet access.
  assign_public_ip = false

  subnet_ids                    = module.vpc.private_subnets
  create_security_group         = false
  security_group_ids            = [module.ecs_sg.id]
  availability_zone_rebalancing = "DISABLED"

  create_task_exec_iam_role = true
  task_exec_iam_role_name   = "${local.name}-execution"
  task_exec_secret_arns = [
    module.db.db_instance_master_user_secret_arn,
    aws_secretsmanager_secret.paperless_secret_key.arn
  ]

  enable_ecs_managed_tags = true

  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100
  health_check_grace_period_seconds  = 300

  deployment_circuit_breaker = {
    enable   = true
    rollback = true
  }

  load_balancer = {
    paperless = {
      target_group_arn = module.alb.target_groups["paperless"].arn
      container_name   = "paperless"
      container_port   = 8000
    }
  }

  container_definitions = {
    paperless = {
      cpu       = 1024
      memory    = 2048
      essential = true
      image     = var.paperless_image

      readonlyRootFilesystem = false

      portMappings = [{
        name          = "paperless"
        containerPort = 8000
        hostPort      = 8000
        protocol      = "tcp"
      }]

      environment = [
        { name = "PAPERLESS_DBENGINE", value = "postgresql" },
        { name = "PAPERLESS_DBHOST", value = module.db.db_instance_address },
        { name = "PAPERLESS_DBPORT", value = "5432" },
        { name = "PAPERLESS_DBNAME", value = "paperless" },
        { name = "PAPERLESS_REDIS", value = "redis://127.0.0.1:6379" },
        { name = "PAPERLESS_TIME_ZONE", value = var.paperless_timezone },
        { name = "PAPERLESS_URL", value = local.paperless_url },
        { name = "PAPERLESS_ALLOWED_HOSTS", value = "${var.domain_name},*" },
        { name = "PAPERLESS_CSRF_TRUSTED_ORIGINS", value = local.paperless_url },
        { name = "PAPERLESS_USE_X_FORWARD_HOST", value = "true" },
        { name = "PAPERLESS_USE_X_FORWARD_PORT", value = "true" },
        { name = "PAPERLESS_ACCOUNT_DEFAULT_HTTP_PROTOCOL", value = "https" },
        { name = "PAPERLESS_TIKA_ENABLED", value = "true" },
        { name = "PAPERLESS_TIKA_GOTENBERG_ENDPOINT", value = "http://127.0.0.1:3000" },
        { name = "PAPERLESS_TIKA_ENDPOINT", value = "http://127.0.0.1:9998" }
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
        },
      ]

      mountPoints = [
        { sourceVolume = "data", containerPath = "/usr/src/paperless/data" },
        { sourceVolume = "media", containerPath = "/usr/src/paperless/media" },
        { sourceVolume = "consume", containerPath = "/usr/src/paperless/consume" },
        { sourceVolume = "export", containerPath = "/usr/src/paperless/export" }
      ]

      healthCheck = {
        command     = ["CMD-SHELL", "curl -fsS http://127.0.0.1:8000/ > /dev/null || exit 1"]
        interval    = 30
        timeout     = 10
        retries     = 5
        startPeriod = 120
      }

      create_cloudwatch_log_group = false
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.paperless.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "paperless"
        }
      }
    }

    valkey = {
      cpu                    = 256
      memory                 = 512
      essential              = true
      image                  = "docker.io/valkey/valkey:9-alpine"
      readonlyRootFilesystem = false

      command = ["valkey-server", "--appendonly", "no"]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.paperless.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "valkey"
        }
      }
    }

    gotenberg = {
      cpu                    = 256
      memory                 = 768
      essential              = true
      image                  = "docker.io/gotenberg/gotenberg:8.36"
      readonlyRootFilesystem = false

      command = ["gotenberg", "--chromium-disable-javascript=true", "--chromium-allow-list=file:///tmp/.*"]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.paperless.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "gotenberg"
        }
      }
    }

    tika = {
      cpu                    = 256
      memory                 = 512
      essential              = true
      image                  = "docker.io/apache/tika:3.3.1.0"
      readonlyRootFilesystem = false

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.paperless.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "tika"
        }
      }
    }
  }

  volume = {
    data = {
      name = "data"
      efs_volume_configuration = {
        file_system_id     = aws_efs_file_system.paperless.id
        transit_encryption = "ENABLED"
        authorization_config = {
          access_point_id = aws_efs_access_point.data.id
        }
      }
    }
    media = {
      name = "media"
      efs_volume_configuration = {
        file_system_id     = aws_efs_file_system.paperless.id
        transit_encryption = "ENABLED"
        authorization_config = {
          access_point_id = aws_efs_access_point.media.id
        }
      }
    }
    consume = {
      name = "consume"
      efs_volume_configuration = {
        file_system_id     = aws_efs_file_system.paperless.id
        transit_encryption = "ENABLED"
        authorization_config = {
          access_point_id = aws_efs_access_point.consume.id
        }
      }
    }
    export = {
      name = "export"
      efs_volume_configuration = {
        file_system_id     = aws_efs_file_system.paperless.id
        transit_encryption = "ENABLED"
        authorization_config = {
          access_point_id = aws_efs_access_point.export.id
        }
      }
    }
  }

  depends_on = [
    aws_efs_mount_target.paperless,
    aws_secretsmanager_secret_version.paperless_secret_key,
    aws_cloudwatch_log_group.paperless
  ]
}
