variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "alb_sg_id" {
  type = string
}

variable "tags" {
  type = map(string)
}

variable "alb_target_group_arn" {
  type        = string
  description = "ARN of the ALB target group to register this instance with"
  default     = ""
}
