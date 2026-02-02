# OpenClaw Secure AWS Deployment
# Hardened environment for running OpenClaw AI assistant in isolation

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "openclaw"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# -----------------------------------------------------------------------------
# DATA SOURCES
# -----------------------------------------------------------------------------

data "aws_availability_zones" "available" {
  state = "available"
}

# Latest Amazon Linux 2023 AMI (free tier eligible)
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_caller_identity" "current" {}

# -----------------------------------------------------------------------------
# VPC & NETWORKING
# -----------------------------------------------------------------------------

resource "aws_vpc" "openclaw" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_internet_gateway" "openclaw" {
  vpc_id = aws_vpc.openclaw.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.openclaw.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-subnet"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.openclaw.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.openclaw.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# VPC Flow Logs for network visibility
resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  count             = var.enable_vpc_flow_logs ? 1 : 0
  name              = "/openclaw/${var.environment}/vpc-flow-logs"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.openclaw_logs.arn

  tags = {
    Name = "${var.project_name}-vpc-flow-logs"
  }
}

resource "aws_iam_role" "vpc_flow_logs" {
  count       = var.enable_vpc_flow_logs ? 1 : 0
  name_prefix = "${var.project_name}-vpc-flow-logs-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-vpc-flow-logs-role"
  }
}

resource "aws_iam_role_policy" "vpc_flow_logs" {
  count       = var.enable_vpc_flow_logs ? 1 : 0
  name_prefix = "${var.project_name}-vpc-flow-logs-"
  role        = aws_iam_role.vpc_flow_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "${aws_cloudwatch_log_group.vpc_flow_logs[0].arn}:*"
      }
    ]
  })
}

resource "aws_flow_log" "vpc" {
  count                    = var.enable_vpc_flow_logs ? 1 : 0
  iam_role_arn             = aws_iam_role.vpc_flow_logs[0].arn
  log_destination          = aws_cloudwatch_log_group.vpc_flow_logs[0].arn
  traffic_type             = "ALL"
  vpc_id                   = aws_vpc.openclaw.id
  max_aggregation_interval = 60

  tags = {
    Name = "${var.project_name}-vpc-flow-log"
  }
}

# -----------------------------------------------------------------------------
# SECURITY GROUPS
# -----------------------------------------------------------------------------

# Main instance security group
resource "aws_security_group" "openclaw_instance" {
  name_prefix = "${var.project_name}-instance-"
  description = "Security group for OpenClaw instance"
  vpc_id      = aws_vpc.openclaw.id

  tags = {
    Name = "${var.project_name}-instance-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# SSH inbound rule (conditional - for debugging)
resource "aws_security_group_rule" "ssh_inbound" {
  count             = var.enable_ssh_access && var.ssh_allowed_cidr != "" ? 1 : 0
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = [var.ssh_allowed_cidr]
  security_group_id = aws_security_group.openclaw_instance.id
  description       = "SSH access for debugging from ${var.ssh_allowed_cidr}"
}

# Validation to ensure SSH CIDR is provided when SSH is enabled
resource "null_resource" "ssh_cidr_validation" {
  count = var.enable_ssh_access && var.ssh_allowed_cidr == "" ? 1 : 0

  provisioner "local-exec" {
    command = "echo 'ERROR: ssh_allowed_cidr must be set when enable_ssh_access is true' && exit 1"
  }
}

# Validation to ensure Tailscale auth key is provided when Tailscale is enabled
resource "null_resource" "tailscale_auth_validation" {
  count = var.enable_tailscale && var.tailscale_auth_key == "" ? 1 : 0

  provisioner "local-exec" {
    command = "echo 'ERROR: tailscale_auth_key must be set when enable_tailscale is true. Use TF_VAR_tailscale_auth_key environment variable.' && exit 1"
  }
}

# Outbound: Allow ALL traffic (simpler and more reliable)
resource "aws_security_group_rule" "all_outbound" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.openclaw_instance.id
  description       = "Allow all outbound traffic"
}

# -----------------------------------------------------------------------------
# IAM ROLE FOR SSM SESSION MANAGER
# -----------------------------------------------------------------------------

resource "aws_iam_role" "openclaw_instance" {
  name_prefix = "${var.project_name}-instance-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-instance-role"
  }
}

# SSM Session Manager policy - allows shell access without SSH
resource "aws_iam_role_policy_attachment" "ssm_managed_instance" {
  role       = aws_iam_role.openclaw_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# CloudWatch Logs policy for session logging
resource "aws_iam_role_policy" "cloudwatch_logs" {
  name_prefix = "${var.project_name}-cw-logs-"
  role        = aws_iam_role.openclaw_instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "${aws_cloudwatch_log_group.openclaw.arn}:*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "openclaw" {
  name_prefix = "${var.project_name}-"
  role        = aws_iam_role.openclaw_instance.name
}

# -----------------------------------------------------------------------------
# KMS KEY FOR LOG ENCRYPTION
# -----------------------------------------------------------------------------

resource "aws_kms_key" "openclaw_logs" {
  description             = "KMS key for OpenClaw CloudWatch log encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM Admin Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = [
          "kms:Create*",
          "kms:Describe*",
          "kms:Enable*",
          "kms:List*",
          "kms:Put*",
          "kms:Update*",
          "kms:Revoke*",
          "kms:Disable*",
          "kms:Get*",
          "kms:Delete*",
          "kms:TagResource",
          "kms:UntagResource",
          "kms:ScheduleKeyDeletion",
          "kms:CancelKeyDeletion"
        ]
        Resource = "*"
      },
      {
        Sid    = "Allow Key Usage for Encryption"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:CallerAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "Allow CloudWatch Logs"
        Effect = "Allow"
        Principal = {
          Service = "logs.${var.aws_region}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/openclaw/*"
          }
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-logs-key"
  }
}

resource "aws_kms_alias" "openclaw_logs" {
  name          = "alias/${var.project_name}-logs"
  target_key_id = aws_kms_key.openclaw_logs.key_id
}

# -----------------------------------------------------------------------------
# CLOUDWATCH LOG GROUP FOR SESSION LOGGING
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "openclaw" {
  name              = "/openclaw/${var.environment}/sessions"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.openclaw_logs.arn

  tags = {
    Name = "${var.project_name}-logs"
  }
}

# -----------------------------------------------------------------------------
# EC2 INSTANCE
# -----------------------------------------------------------------------------

resource "aws_instance" "openclaw" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.openclaw_instance.id]
  iam_instance_profile   = aws_iam_instance_profile.openclaw.name

  # Encrypted root volume
  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true

    tags = {
      Name = "${var.project_name}-root-volume"
    }
  }

  # Disable IMDSv1 (require IMDSv2 for better security)
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # Require IMDSv2
    http_put_response_hop_limit = 2          # Allow for Docker containers
  }

  # Enable detailed monitoring for better security visibility
  # Note: Basic monitoring is free, detailed monitoring has additional costs
  monitoring = var.environment == "prod" ? true : false

  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    enable_tailscale   = var.enable_tailscale
    tailscale_auth_key = var.tailscale_auth_key
    tailscale_hostname = var.tailscale_hostname
  }))

  tags = {
    Name = "${var.project_name}-instance"
  }

  # Prevent accidental termination
  disable_api_termination = var.termination_protection

  # Ensure networking is ready before launching
  depends_on = [
    aws_route_table_association.public,
    aws_internet_gateway.openclaw
  ]

  lifecycle {
    ignore_changes = [ami] # Don't recreate on AMI updates
  }
}

# -----------------------------------------------------------------------------
# SSM SESSION MANAGER PREFERENCES (for logging)
# -----------------------------------------------------------------------------

resource "aws_ssm_document" "session_manager_prefs" {
  name            = "${var.project_name}-SessionManagerPrefs"
  document_type   = "Session"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "1.0"
    description   = "Session Manager preferences for OpenClaw"
    sessionType   = "Standard_Stream"
    inputs = {
      cloudWatchLogGroupName      = aws_cloudwatch_log_group.openclaw.name
      cloudWatchEncryptionEnabled = true
      cloudWatchStreamingEnabled  = true
      idleSessionTimeout          = "60"
      maxSessionDuration          = "480"
      shellProfile = {
        linux = "cd ~ && bash"
      }
    }
  })

  tags = {
    Name = "${var.project_name}-ssm-prefs"
  }
}
