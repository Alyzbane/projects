output "vpc" {
  description = "Core VPC identifiers"
  value = {
    id            = aws_vpc.main_vpc.id
    igw_id        = aws_internet_gateway.igw_main.id
    natgw_id      = aws_nat_gateway.nat_main.id
    natgw_ip      = aws_eip.nat_main.public_ip
    public_rt_id  = aws_route_table.public_main_vpc.id
    private_rt_id = aws_route_table.private_main_vpc.id
  }
}

output "subnets" {
  description = "Public and private subnet IDs keyed by AZ"
  value = {
    public  = { for k, s in aws_subnet.public : k => s.id }
    private = { for k, s in aws_subnet.private : k => s.id }
  }
}

output "vpc_endpoints" {
  description = "VPC endpoint identifiers and DNS entries"
  value = {
    kms_id  = aws_vpc_endpoint.kms.id
    kms_dns = aws_vpc_endpoint.kms.dns_entry
    s3_id   = aws_vpc_endpoint.s3.id
  }
}

output "instances" {
  description = "Instance IDs and IPs keyed by role"
  value = {
    public = { for k, i in aws_instance.public : k => {
      id         = i.id
      public_ip  = i.public_ip
      private_ip = i.private_ip
    } }
    private = { for k, i in aws_instance.private : k => {
      id         = i.id
      private_ip = i.private_ip
    } }
  }
}


output "security_group" {
  description = "Shared ICMP-only security group ID"
  value       = aws_security_group.icmp.id
}
