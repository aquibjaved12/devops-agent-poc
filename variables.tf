variable "region" {}

variable "ami_id" {}

variable "instance_type" {}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "create_vpc" {
  default = true
}

variable "log_group_name" {
  description = "Name of the application log group"
  type        = string
}

variable "os_log_group_name" {
  description = "Name of the OS-level log group"
  type        = string
}