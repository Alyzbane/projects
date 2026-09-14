locals {
  common_tags = {
    Environment = "dev"
    Owner       = "ASE"
  }

  public_subnets = {
    az1 = {
      availability_zone = "us-east-1a"
      cidr_block        = "10.0.0.0/24"
      tags = {
        Name = "VPC A Public Subnet AZ1"
      }
    }
    az2 = {
      availability_zone = "us-east-1b"
      cidr_block        = "10.0.2.0/24"
      tags = {
        Name = "VPC A Public Subnet AZ2"
      }
    }
  }

  private_subnets = {
    az1 = {
      availability_zone = "us-east-1a"
      cidr_block        = "10.0.1.0/24"
      tags = {
        Name = "VPC A Private Subnet AZ1"
      }
    }
    az2 = {
      availability_zone = "us-east-1b"
      cidr_block        = "10.0.3.0/24"
      tags = {
        Name = "VPC A Private Subnet AZ2"
      }
    }
  }
}
