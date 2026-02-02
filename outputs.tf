# -----------------------------------------------------------------------------
# OUTPUTS
# -----------------------------------------------------------------------------

output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.openclaw.id
}

output "instance_private_ip" {
  description = "Private IP address of the instance"
  value       = aws_instance.openclaw.private_ip
  sensitive   = true
}

output "instance_public_ip" {
  description = "Public IP address (ephemeral - may change on restart)"
  value       = aws_instance.openclaw.public_ip
  sensitive   = true
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.openclaw.id
}

output "security_group_id" {
  description = "ID of the instance security group"
  value       = aws_security_group.openclaw_instance.id
}

output "iam_role_arn" {
  description = "ARN of the IAM role attached to the instance"
  value       = aws_iam_role.openclaw_instance.arn
}

output "cloudwatch_log_group" {
  description = "CloudWatch log group for session logs"
  value       = aws_cloudwatch_log_group.openclaw.name
}

output "tailscale_ssh" {
  description = "SSH via Tailscale"
  value       = var.enable_tailscale ? "ssh ec2-user@${var.tailscale_hostname}" : "Tailscale disabled"
}

output "ssm_session_command" {
  description = "AWS CLI command to start an SSM session"
  value       = "aws ssm start-session --target ${aws_instance.openclaw.id} --region ${var.aws_region}"
}

output "next_steps" {
  description = "What to do after deployment"
  value       = <<-EOT

    ============================================
    OpenClaw Instance Ready!
    ============================================

    1. Connect via Tailscale:
       ssh ec2-user@${var.tailscale_hostname}

    2. Complete setup:
       curl -fsSL https://openclaw.ai/install.sh | bash
       openclaw onboard

    3. If Tailscale not working, use SSM:
       aws ssm start-session --target ${aws_instance.openclaw.id} --region ${var.aws_region}

    4. Check setup logs:
       sudo cat /var/log/openclaw-setup.log

    ============================================
  EOT
}
