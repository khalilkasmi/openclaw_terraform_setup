# OpenClaw Secure AWS Deployment

Terraform module to deploy [OpenClaw](https://openclaw.ai) in a hardened AWS environment.

## Security Features

- **No inbound ports** - Instance has no SSH or other ports open from the internet (by default)
- **Tailscale VPN** - Optional secure remote access via Tailscale (recommended)
- **SSM Session Manager** - Access via IAM-authenticated, audited sessions
- **Encrypted storage** - EBS volume encryption enabled
- **IMDSv2 required** - Protection against SSRF attacks
- **Docker sandboxing** - OpenClaw sessions run in isolated containers
- **Dedicated user** - OpenClaw runs as non-root user
- **Session logging** - All SSM sessions logged to CloudWatch
- **Kernel hardening** - Security sysctl parameters applied

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.0
- AWS Session Manager plugin installed ([install guide](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html))

## Quick Start

```bash
# 1. Clone and enter directory
cd terraform

# 2. Create your variables file
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your API keys

# 3. Initialize Terraform
terraform init

# 4. Review the plan
terraform plan

# 5. Deploy
terraform apply

# 6. Connect to instance (choose one method)
# Option A: Via SSM Session Manager
aws ssm start-session --target <instance-id> --region eu-central-1

# Option B: Via Tailscale (if enabled)
# The instance will appear in your Tailnet with the configured hostname
ssh openclaw@<tailscale-hostname>

# 7. Install openclaw and run onboarding
curl -fsSL https://openclaw.ai/install.sh | bash
openclaw onboard
```

## Connecting to the Instance

### Via SSM Session Manager

```bash
# Get instance ID from terraform output
terraform output instance_id

# Connect via SSM
aws ssm start-session --target i-xxxxxxxxx --region eu-central-1

# Or use the full command from output
terraform output -raw ssm_session_command | bash
```

### Via Tailscale (Recommended)

If you enabled Tailscale during deployment:

1. The instance will automatically join your Tailnet
2. Find the instance in your Tailscale admin console: https://login.tailscale.com/admin/machines
3. Connect via SSH using the configured hostname (default: `openclaw`):
   ```bash
   ssh openclaw@openclaw
   ```

Tailscale provides:
- Encrypted, authenticated VPN access
- No need to expose SSH ports
- Easy access from any device in your Tailnet
- Better security than direct SSH exposure

## Cost Estimate

### Free Tier Option (t2.micro)

| Resource | Free Tier | After Free Tier |
|----------|-----------|-----------------|
| t2.micro | 750 hrs/month (12 months) | ~$8.50/month |
| EBS 20GB | 30 GB/month | ~$1.60/month |
| CloudWatch Logs | 5GB ingest | ~$0.50/GB |

### Recommended Option (t3.small - default)

| Resource | Monthly Cost |
|----------|--------------|
| t3.small | ~$15/month |
| EBS 20GB | ~$1.60/month |
| CloudWatch Logs | ~$0.50/GB |

**Note:** NAT Gateway was intentionally avoided (~$32/month) by using a public subnet with locked-down security groups. The default instance type is `t3.small` for better performance with OpenClaw, but you can use `t2.micro` for free tier eligibility.

## Variables

### Required

| Name | Description | Default |
|------|-------------|---------|
| `anthropic_api_key` | Anthropic API key for Claude models | (required) |

### AWS Configuration

| Name | Description | Default |
|------|-------------|---------|
| `aws_region` | AWS region to deploy resources | `eu-central-1` |
| `instance_type` | EC2 instance type (t2/t3 family) | `t3.small` |
| `root_volume_size` | EBS volume size (GB) | `20` |
| `environment` | Environment name (dev/staging/prod) | `dev` |
| `project_name` | Project name for resource naming | `openclaw` |

### Security & Access

| Name | Description | Default |
|------|-------------|---------|
| `enable_tailscale` | Enable Tailscale VPN access | `true` |
| `tailscale_auth_key` | Tailscale auth key | (required if enabled) |
| `tailscale_hostname` | Hostname in Tailnet | `openclaw` |
| `enable_ssh_access` | Enable direct SSH access | `false` |
| `ssh_allowed_cidr` | CIDR allowed to SSH | `0.0.0.0/0` |
| `ssh_key_name` | Existing EC2 key pair name | `""` |

### OpenClaw Configuration

| Name | Description | Default |
|------|-------------|---------|
| `enable_docker_sandbox` | Enable Docker sandboxing | `true` |
| `openai_api_key` | OpenAI API key (optional) | `""` |
| `openclaw_user` | Linux user for OpenClaw | `openclaw` |

### Other

| Name | Description | Default |
|------|-------------|---------|
| `log_retention_days` | CloudWatch log retention | `30` |
| `termination_protection` | Enable termination protection | `false` |
| `vpc_cidr` | VPC CIDR block | `20.0.0.0/16` |
| `public_subnet_cidr` | Public subnet CIDR | `20.0.1.0/24` |

See `variables.tf` for detailed descriptions and validation rules.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         AWS VPC                              │
│  ┌───────────────────────────────────────────────────────┐  │
│  │                   Public Subnet                        │  │
│  │                                                        │  │
│  │   ┌─────────────────────────────────────────────┐     │  │
│  │   │           EC2 Instance (t2.micro)            │     │  │
│  │   │                                              │     │  │
│  │   │   ┌──────────────────────────────────────┐  │     │  │
│  │   │   │         OpenClaw Gateway              │  │     │  │
│  │   │   │         (localhost:18789)             │  │     │  │
│  │   │   └──────────────────────────────────────┘  │     │  │
│  │   │                    │                        │     │  │
│  │   │   ┌──────────────────────────────────────┐  │     │  │
│  │   │   │    Docker Containers (Sandboxed)     │  │     │  │
│  │   │   │         Session Isolation            │  │     │  │
│  │   │   └──────────────────────────────────────┘  │     │  │
│  │   │                                              │     │  │
│  │   │   Security Group: NO INBOUND RULES          │     │  │
│  │   │   Outbound: HTTPS, HTTP, DNS only           │     │  │
│  │   └─────────────────────────────────────────────┘     │  │
│  │                         │                              │  │
│  └─────────────────────────│──────────────────────────────┘  │
│                            │                                  │
│            Internet Gateway (outbound only)                   │
└────────────────────────────│──────────────────────────────────┘
                             │
                    ┌────────┴────────┐
                    │   SSM Session   │
                    │    Manager      │
                    │  (IAM Auth)     │
                    └────────┬────────┘
                             │
                        Your Machine
```

## Cleanup

```bash
terraform destroy
```

## Security Considerations

1. **API Keys**: Store in `terraform.tfvars` (gitignored) or use AWS Secrets Manager
2. **Tailscale Setup**: 
   - Get auth key from https://login.tailscale.com/admin/settings/keys
   - Create a "Reusable" and "Ephemeral" key for best security
   - The instance will automatically join your Tailnet on first boot
3. **Free Tier Limits**: t2.micro has 1GB RAM - may struggle with heavy workloads. Consider t3.small for better performance.
4. **Egress Traffic**: Instance can reach the internet for integrations - monitor CloudWatch logs
5. **Session Access**: 
   - SSM: Anyone with IAM permissions can start SSM sessions - use IAM policies to restrict
   - Tailscale: Only devices in your Tailnet can access the instance
6. **SSH Access**: Only enable `enable_ssh_access` for debugging. Use Tailscale or SSM for regular access.
