#!/usr/bin/env bash
set -euo pipefail

# Localstack variable
AWS_CMD="lstk aws"

echo "=== VPCs ==="
${AWS_CMD} ec2 describe-vpcs \
  --query 'Vpcs[].{VpcId:VpcId,CIDR:CidrBlock,State:State}' \
  --output table

echo
echo "=== Peering ==="
${AWS_CMD} ec2 describe-vpc-peering-connections \
  --query 'VpcPeeringConnections[].{Id:VpcPeeringConnectionId,Status:Status.Code,Requester:RequesterVpcInfo.VpcId,Accepter:AccepterVpcInfo.VpcId}' \
  --output table

echo
echo "=== Routes ==="
${AWS_CMD} ec2 describe-route-tables \
  --query 'RouteTables[].{RT:RouteTableId,VPC:VpcId,Routes:Routes[].DestinationCidrBlock}' \
  --output json

echo
echo "Inspect complete."
