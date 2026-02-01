# -----------------------------------------------------------------------------
# OUTPUTS
# -----------------------------------------------------------------------------

output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.openclaw.id
}

output "instance_public_ip" {
  description = "Public IP address"
  value       = aws_instance.openclaw.public_ip
}

output "tailscale_ssh" {
  description = "SSH via Tailscale"
  value       = var.enable_tailscale ? "ssh ec2-user@${var.tailscale_hostname}" : "Tailscale disabled"
}

output "ssm_command" {
  description = "Connect via SSM (backup)"
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
       openclaw onboard

    3. If Tailscale not working, use SSM:
       aws ssm start-session --target ${aws_instance.openclaw.id} --region ${var.aws_region}

    4. Check setup logs:
       sudo cat /var/log/openclaw-setup.log

    ============================================
  EOT
}
