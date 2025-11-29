variable "aws_region" {
  default = "us-east-1"
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "azs" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b"]
}

variable "project" {
  default = "moveo"
}

variable "environment" {
  default = "dev"
}

variable "owner" {
  default = "ohad"
}
