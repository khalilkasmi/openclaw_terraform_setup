# -----------------------------------------------------------------------------
# VARIABLES
# -----------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "eu-central-1"
}

variable "environment" {
  description = "Environment name (dev, staging, or prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Project name used for resource naming (lowercase, alphanumeric, hyphens allowed)"
  type        = string
  default     = "openclaw"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,20}$", var.project_name))
    error_message = "Project name must start with a letter, contain only lowercase letters, numbers, and hyphens, and be 2-21 characters long."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC (must be RFC 1918 private range)"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(regex("^(10\\.|172\\.(1[6-9]|2[0-9]|3[01])\\.|192\\.168\\.)", var.vpc_cidr))
    error_message = "VPC CIDR must be a valid RFC 1918 private IP range (10.0.0.0/8, 172.16.0.0/12, or 192.168.0.0/16)."
  }
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet (must be within VPC CIDR)"
  type        = string
  default     = "10.0.1.0/24"
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

# Note: The following variables are defined for documentation and future use.
# OpenClaw installation is performed manually after instance provisioning.

variable "openclaw_user" {
  description = "Linux user to run OpenClaw as (used in documentation)"
  type        = string
  default     = "ec2-user"
}

variable "enable_docker_sandbox" {
  description = "Enable Docker sandboxing for OpenClaw sessions (reserved for future use)"
  type        = bool
  default     = true
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

variable "enable_vpc_flow_logs" {
  description = "Enable VPC flow logs for network visibility and security monitoring (recommended for production)"
  type        = bool
  default     = true
}

variable "termination_protection" {
  description = "Enable termination protection on the instance"
  type        = bool
  default     = false
}

variable "enable_ssh_access" {
  description = "Enable SSH access for debugging (set to false when using Tailscale)"
  type        = bool
  default     = false
}

variable "ssh_allowed_cidr" {
  description = "CIDR block allowed to SSH (use your IP, e.g., 1.2.3.4/32). Required when enable_ssh_access is true."
  type        = string
  default     = ""

  validation {
    condition     = var.ssh_allowed_cidr == "" || can(cidrhost(var.ssh_allowed_cidr, 0))
    error_message = "ssh_allowed_cidr must be a valid CIDR block (e.g., 1.2.3.4/32)."
  }
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
  description = "Tailscale auth key (get from https://login.tailscale.com/admin/settings/keys). Required when enable_tailscale is true."
  type        = string
  sensitive   = true
  default     = ""

  validation {
    condition     = var.tailscale_auth_key == "" || can(regex("^tskey-", var.tailscale_auth_key))
    error_message = "Tailscale auth key must start with 'tskey-' prefix."
  }
}

variable "tailscale_hostname" {
  description = "Hostname for this machine in your Tailnet"
  type        = string
  default     = "openclaw"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,62}$", var.tailscale_hostname))
    error_message = "Tailscale hostname must be lowercase alphanumeric with hyphens, 1-63 characters, and start with a letter or number."
  }
}
