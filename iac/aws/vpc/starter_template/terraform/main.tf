# VPC

resource "aws_vpc" "main_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, { Name = "VPC A" })
}

# Building the Subnets

resource "aws_subnet" "public" {
  for_each = local.public_subnets

  vpc_id                  = aws_vpc.main_vpc.id
  availability_zone       = each.value.availability_zone
  cidr_block              = each.value.cidr_block
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, each.value.tags)
}

resource "aws_subnet" "private" {
  for_each = local.private_subnets

  vpc_id            = aws_vpc.main_vpc.id
  availability_zone = each.value.availability_zone
  cidr_block        = each.value.cidr_block

  tags = merge(local.common_tags, each.value.tags)
}

# Network ACL

resource "aws_network_acl" "main" {
  vpc_id = aws_vpc.main_vpc.id
  tags   = merge(local.common_tags, { Name = "Main-NACL" })
}

resource "aws_network_acl_association" "public" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  network_acl_id = aws_network_acl.main.id
}

resource "aws_network_acl_association" "private" {
  for_each       = aws_subnet.private
  subnet_id      = each.value.id
  network_acl_id = aws_network_acl.main.id
}

## Rules

resource "aws_network_acl_rule" "allow_all_inbound" {
  network_acl_id = aws_network_acl.main.id
  rule_number    = 100
  egress         = false
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
}

resource "aws_network_acl_rule" "allow_all_outbound" {
  network_acl_id = aws_network_acl.main.id
  rule_number    = 200
  egress         = true
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
}

# Route table

## Public

resource "aws_route_table" "public_main_vpc" {
  vpc_id = aws_vpc.main_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw_main.id
  }

  tags = merge(local.common_tags, { Name = "Public Route Table Main VPC" })
}

resource "aws_route_table_association" "public_subnets" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public_main_vpc.id
}

## Private

resource "aws_route_table" "private_main_vpc" {
  vpc_id = aws_vpc.main_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_main.id
  }

  tags = merge(local.common_tags, { Name = "Private Route Table Main VPC" })
}

resource "aws_route_table_association" "private_subnets" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private_main_vpc.id
}

# IGW

resource "aws_internet_gateway" "igw_main" {
  vpc_id = aws_vpc.main_vpc.id
  tags   = merge(local.common_tags, { Name = "Main-IGW" })
}

# NAT Gateway

resource "aws_eip" "nat_main" {
  domain = "vpc"
  tags   = merge(local.common_tags, { Name = "VPC A NATGW EIP" })
}

resource "aws_nat_gateway" "nat_main" {
  allocation_id     = aws_eip.nat_main.id
  subnet_id         = aws_subnet.public["az1"].id
  connectivity_type = "public"

  tags = merge(local.common_tags, { Name = "VPC A NATGW" })

  depends_on = [aws_internet_gateway.igw_main]
}

# VPC Endpoints

data "aws_security_group" "default" {
  vpc_id = aws_vpc.main_vpc.id
  name   = "default"
}

## KMS Interface VPC Endpoint

resource "aws_vpc_endpoint" "kms" {
  vpc_id            = aws_vpc.main_vpc.id
  service_name      = "com.amazonaws.${var.aws_region}.kms"
  vpc_endpoint_type = "Interface"

  subnet_ids = [
    aws_subnet.private["az1"].id,
    aws_subnet.private["az2"].id
  ]

  security_group_ids = [data.aws_security_group.default.id]

  private_dns_enabled = true

  tags = merge(
    local.common_tags,
    { Name = "VPC A KMS Endpoint" }
  )
}

## S3 Gateway VPC Endpoint

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main_vpc.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = [
    aws_route_table.public_main_vpc.id,
    aws_route_table.private_main_vpc.id
  ]

  tags = merge(local.common_tags, {
    Name = "VPC A S3 Endpoint"
  })
}

# EC2 Instances

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}


resource "aws_security_group" "icmp" {
  name        = "VPC A Security Group"
  description = "Open-up ports for ICMP"
  vpc_id      = aws_vpc.main_vpc.id

  ingress {
    description = "All ICMP - IPv4"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Security groups are stateful, so no explicit egress rule is
  # required for the instance to respond to an inbound ping.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "VPC A Security Group" })
}

# Public instances
resource "aws_instance" "public" {
  for_each = aws_subnet.public

  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = var.instance_type
  subnet_id                   = each.value.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.icmp.id]
  iam_instance_profile        = var.instance_profile_name

  private_ip = each.key == "az2" ? "10.0.2.100" : null

  tags = merge(local.common_tags, {
    Name = "VPC A Public Server ${each.key}"
  })
}

# Private instances
resource "aws_instance" "private" {
  for_each = aws_subnet.private

  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = var.instance_type
  subnet_id                   = each.value.id
  associate_public_ip_address = false
  vpc_security_group_ids      = [aws_security_group.icmp.id]
  iam_instance_profile        = var.instance_profile_name

  private_ip = each.key == "az1" ? "10.0.1.100" : null

  tags = merge(local.common_tags, {
    Name = "VPC A Private Server ${each.key}"
  })

  depends_on = [aws_nat_gateway.nat_main]
}
