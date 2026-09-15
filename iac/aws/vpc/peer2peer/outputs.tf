output "vpc_ids" {
  description = "Map of VPC names to their IDs"
  value       = { for k, v in aws_vpc.this : k => v.id }
}

output "peering_ids" {
  description = "Map of VPC peering connection names to their IDs"
  value = {
    shared_to_app  = aws_vpc_peering_connection.shared_to_app.id
    shared_to_data = aws_vpc_peering_connection.shared_to_data.id
  }
}