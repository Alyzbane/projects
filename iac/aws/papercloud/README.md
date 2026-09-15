# PaperCloud

Paperless-ngx on AWS using Terraform.

## Scope

YAGNI first milestone:

- VPC with public and private subnets
- Public ALB
- ECS Fargate service
- Paperless-ngx + Valkey sidecar
- RDS PostgreSQL in private subnets
- EFS for Paperless persistent directories
- Secrets Manager
- CloudWatch logs
- No NAT Gateway

## Why this shape

ECS tasks use public subnets with public IPs to avoid NAT Gateway cost. The ECS security group only accepts Paperless traffic from the ALB. RDS and EFS remain reachable only inside the VPC.

This is a cost-conscious learning environment, not a hardened production environment. The next security milestone is HTTPS with ACM and a domain, followed by Cognito/OIDC and tighter egress.

## Prerequisites

- AWS account with credentials configured for Terraform
- Terraform >= 1.11.1
- An AWS region with the selected AZs and `db.t4g.micro` support

## Deploy

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply
terraform output paperless_url
```

Open the URL and create the initial Paperless admin account through the application flow.

## Destroy

```bash
terraform destroy
```

`skip_final_snapshot = true` and deletion protection are intentionally disabled for the dev environment. Do not copy those settings blindly into a production environment.

## Next milestones

1. ACM + Route 53 HTTPS
2. Cognito OIDC
3. S3 backup/export pipeline
4. Datadog
5. GitHub Actions + Terraform plan/apply workflow
6. Trivy, Gitleaks, Checkov
