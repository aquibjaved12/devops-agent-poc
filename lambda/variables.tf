variable "alert_email" {
  description = "Email address to send incident alerts"
  type        = string
  default     = "aquib.javed@minfytech.com"  
}

variable "github_token" {
  description = "GitHub Personal Access Token for deployment info"
  type        = string
  sensitive   = true
  default     = ""
}

variable "github_repo" {
  description = "GitHub repo in format owner/repo-name"
  type        = string
  default     = "aquibjaved12/devops-agent-poc"  
}

variable "devops_agent_url" {
  description = "Direct URL to DevOps Agent Web App"
  type        = string
  default     = "https://console.aws.amazon.com/devops-agent"
}

variable "instance_id" {
  description = "EC2 instance ID (default for enrichment)"
  type        = string
}