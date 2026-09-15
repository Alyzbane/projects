# ===================================================
# VPCs
# ===================================================

resource "aws_vpc" "this" {
  for_each = local.vpcs

  cidr_block           = each.value
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "network-${each.key}"
  }
}

resource "aws_subnet" "private_a" {
  for_each = aws_vpc.this

  vpc_id            = each.value.id
  cidr_block        = cidrsubnet(local.vpcs[each.key], 8, 10)
  availability_zone = "us-east-1a"

  tags = {
    Name = "network-${each.key}-private-a"
  }
}

resource "aws_route_table" "private" {
  for_each = aws_vpc.this

  vpc_id = each.value.id

  tags = {
    Name = "network-${each.key}-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private_a

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}

resource "aws_security_group" "default" {
  for_each = aws_vpc.this

  name        = "network-${each.key}"
  description = "Baseline security boundary for ${each.key}"
  vpc_id      = each.value.id

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ===================================================
# VPC Peering Connections (Auto-Accept)
# ===================================================

resource "aws_vpc_peering_connection" "shared_to_app" {
  vpc_id      = aws_vpc.this["shared"].id
  peer_vpc_id = aws_vpc.this["app"].id
  auto_accept = true

  tags = {
    Name = "shared-to-app"
  }
}

resource "aws_vpc_peering_connection" "shared_to_data" {
  vpc_id      = aws_vpc.this["shared"].id
  peer_vpc_id = aws_vpc.this["data"].id
  auto_accept = true

  tags = {
    Name = "shared-to-data"
  }
}

# ===================================================
# Routes for VPC Peering Connections
# ===================================================

resource "aws_route" "shared_to_app" {
  route_table_id            = aws_route_table.private["shared"].id
  destination_cidr_block    = local.vpcs["app"]
  vpc_peering_connection_id = aws_vpc_peering_connection.shared_to_app.id
}

resource "aws_route" "app_to_shared" {
  route_table_id            = aws_route_table.private["app"].id
  destination_cidr_block    = local.vpcs["shared"]
  vpc_peering_connection_id = aws_vpc_peering_connection.shared_to_app.id
}

resource "aws_route" "shared_to_data" {
  route_table_id            = aws_route_table.private["shared"].id
  destination_cidr_block    = local.vpcs["data"]
  vpc_peering_connection_id = aws_vpc_peering_connection.shared_to_data.id
}

resource "aws_route" "data_to_shared" {
  route_table_id            = aws_route_table.private["data"].id
  destination_cidr_block    = local.vpcs["shared"]
  vpc_peering_connection_id = aws_vpc_peering_connection.shared_to_data.id
}
