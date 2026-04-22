variable "log_group_name" {
  description = "Name of the application log group"
  type        = string
}

variable "os_log_group_name" {
  description = "Name of the OS-level log group"
  type        = string
}

variable "retention_days" {
  description = "Log retention period in days"
  type        = number
  default     = 30
}

variable "instance_id" {
  description = "EC2 instance ID to monitor"
  type        = string
}