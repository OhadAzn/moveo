variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnets" {
  type = list(string)
}

variable "instance_id" {
  type = string
}

variable "tags" {
  type = map(string)
}
