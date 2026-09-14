variable "aws_region" {
  description = "Default AWS AZ"
  type        = string
  default     = "us-east-1"
}

variable "instance_profile_name" {
  description = "Name of the pre-existing IAM instance profile created in the workshop prerequisites"
  type        = string
  default     = "NetworkingWorkshopInstanceProfile"
}

variable "instance_type" {
  description = "Default EC2 instance type"
  type        = string
  default     = "t3.micro"

}
