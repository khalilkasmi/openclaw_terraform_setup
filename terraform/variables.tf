# -----------------------------------------------------------------------------
# REQUIRED VARIABLES
# -----------------------------------------------------------------------------

variable "anthropic_api_key" {
  description = "Anthropic API key for Claude models (required for OpenClaw)"
  type        = string
  sensitive   = true
  default     = ""
}

# -----------------------------------------------------------------------------
# OPTIONAL VARIABLES
# -----------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "eu-central-1"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "openclaw"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "20.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "20.0.1.0/24"
}

variable "instance_type" {
  description = "EC2 instance type (t3.small recommended for OpenClaw - ~$15/month)"
  type        = string
  default     = "t3.small"

  validation {
    condition     = can(regex("^t[23]\\.(micro|small|medium|large|xlarge)$", var.instance_type))
    error_message = "Instance type must be a valid t2 or t3 instance type."
  }
}

variable "root_volume_size" {
  description = "Size of root EBS volume in GB"
  type        = number
  default     = 20

  validation {
    condition     = var.root_volume_size >= 8 && var.root_volume_size <= 100
    error_message = "Root volume size must be between 8 and 100 GB."
  }
}

variable "openclaw_user" {
  description = "Linux user to run OpenClaw as"
  type        = string
  default     = "openclaw"
}

variable "enable_docker_sandbox" {
  description = "Enable Docker sandboxing for OpenClaw sessions"
  type        = bool
  default     = true
}

variable "openai_api_key" {
  description = "OpenAI API key (optional, for GPT models)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Log retention must be a valid CloudWatch retention period."
  }
}

variable "termination_protection" {
  description = "Enable termination protection on the instance"
  type        = bool
  default     = false
}

variable "ssh_key_name" {
  description = "Name of existing EC2 key pair for SSH access (optional, for debugging)"
  type        = string
  default     = ""
}

variable "enable_ssh_access" {
  description = "Enable SSH access for debugging (set to false when using Tailscale)"
  type        = bool
  default     = false
}

variable "ssh_allowed_cidr" {
  description = "CIDR block allowed to SSH (use your IP, e.g., 1.2.3.4/32)"
  type        = string
  default     = "0.0.0.0/0"
}

# -----------------------------------------------------------------------------
# TAILSCALE CONFIGURATION
# -----------------------------------------------------------------------------

variable "enable_tailscale" {
  description = "Enable Tailscale for secure remote access (recommended)"
  type        = bool
  default     = true
}

variable "tailscale_auth_key" {
  description = "Tailscale auth key (get from https://login.tailscale.com/admin/settings/keys)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "tailscale_hostname" {
  description = "Hostname for this machine in your Tailnet"
  type        = string
  default     = "openclaw"
}
