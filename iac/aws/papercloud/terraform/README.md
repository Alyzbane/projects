# Terraform Design Notes

This directory contains the Terraform configuration for the PaperCloud demo deployment.

## Things to note on design

### RDS deletion behavior

The RDS configuration currently uses these settings:

```hcl
deletion_protection     = false
skip_final_snapshot     = true
```

The first setting allows Terraform to destroy the database. The second setting tells RDS not to create a final snapshot during deletion.

Together, these settings mean that:

```bash
terraform destroy
```

can permanently delete the database and its data without a final recovery snapshot. This is acceptable for a disposable development or demonstration environment, but it is not appropriate for most production databases.

For a production environment, consider:

```hcl
deletion_protection     = true
skip_final_snapshot     = false
final_snapshot_identifier = "papercloud-final"
```

With `deletion_protection = true`, an intentional destroy requires changing the setting back to `false` and applying that change first. A final snapshot should also be retained according to the project's backup and retention requirements.

### Private ECS subnets and one NAT Gateway

The ECS task runs in private subnets with no public IP address. A single NAT Gateway is shared by the private subnets so the task can reach external HTTPS services, pull images, and contact AWS services without being directly reachable from the internet.

Using one NAT Gateway reduces cost compared with one per Availability Zone, but it is not fully highly available. A production environment with stronger availability requirements should use one NAT Gateway per Availability Zone.

### ALB to ECS traffic

The ALB security group allows outbound TCP traffic only on port `8000`, and the rule references the ECS task security group. The ECS service uses `module.ecs_sg.id` for its task security group, so the ALB can reach the Paperless container without allowing unrestricted outbound traffic.

### ALB deletion protection

The ALB uses:

```hcl
enable_deletion_protection = false
```

This allows `make destroy` to remove the load balancer during cleanup. Enable deletion protection for an environment where accidental removal would be costly.

### EFS persistence

Paperless data, media, consume, and export directories are stored on encrypted EFS access points. Destroying the Terraform resources still removes the managed EFS file system, so application documents should be backed up separately before cleanup.

### DNS and ACM validation

When Terraform creates a hosted zone for a subdomain, the hosted zone's four Route 53 nameservers must be registered as `NS` records in the parent DNS zone. ACM validation waits for the DNS validation CNAME to be publicly resolvable, so missing delegation can cause `aws_acm_certificate_validation` to wait and eventually time out.

Use the staged setup from the project README:

```bash
make dns-zone
dig NS paper.example.com
make apply
```

Replace `paper.example.com` with the configured domain. The delegation step is not needed when `route53_zone_id` points to an existing authoritative Route 53 zone.

### Protected application paths

The ALB forwards the configured administrative and user-management paths only when the request source matches `admin_allowed_cidrs`. Requests to those paths from other source addresses receive an HTTP 403 response. This is an additional network-layer control and should not replace Paperless authentication, least-privilege access, or other application security controls.

### ECS outbound access

The ECS security group does not allow unrestricted outbound traffic. Its egress rules are limited to:

- TCP `5432` within the VPC for PostgreSQL.
- TCP `2049` within the VPC for EFS.
- UDP and TCP `53` within the VPC for DNS resolution.
- TCP `443` to the internet for container image pulls, CloudWatch and AWS service calls, and required external HTTPS calls.

The RDS and EFS rules use the VPC CIDR instead of directly referencing those security groups. The RDS and EFS security groups already reference the ECS security group for inbound access, and using references in both directions would create a Terraform dependency cycle. The port restrictions still prevent arbitrary VPC traffic from the ECS task.
