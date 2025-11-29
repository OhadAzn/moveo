variable "vpc_cidr" {
  type = string
}

variable "name" {
  type = string
}

variable "azs" {
  type = list(string)
}

variable "tags" {
  type = map(string)
}
