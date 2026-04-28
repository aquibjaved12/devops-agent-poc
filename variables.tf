variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "ami_id" {
  description = "AMI ID for EC2 instance (Amazon Linux 2023)"
  type        = string
  default     = "ami-098e39bafa7e7303d"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "create_vpc" {
  description = "Whether to create a new VPC"
  type        = bool
  default     = true
}

variable "log_group_name" {
  description = "Name of the application log group"
  type        = string
  default     = "devops-agent-app-logs"
}

variable "os_log_group_name" {
  description = "Name of the OS-level log group"
  type        = string
  default     = "devops-agent-os-logs"
}

variable "github_actions_username" {
  description = "IAM username used by GitHub Actions CI/CD"
  type        = string
  default     = "aquib"
}

variable "alert_email" {
  description = "Email for SES incident alerts"
  type        = string
  default     = ""
}

variable "github_token" {
  description = "GitHub PAT for deployment info"
  type        = string
  sensitive   = true
  default     = ""
}

variable "github_repo" {
  description = "GitHub repo owner/name"
  type        = string
  default     = "aquibjaved12/devops-agent-poc"
}

variable "devops_agent_url" {
  description = "DevOps Agent Web App URL"
  type        = string
  default     = "https://console.aws.amazon.com/devops-agent"
}