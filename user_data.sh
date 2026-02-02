#!/bin/bash
set -euo pipefail

# Redirect all output to log file while also showing on console
exec > >(tee /var/log/openclaw-setup.log) 2>&1

echo "=== OpenClaw Setup Started: $(date) ==="

# Use IMDSv2 for metadata access (more secure)
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
echo ">>> Instance ID: $(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id || echo 'unknown')"
echo ">>> Region: $(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/region || echo 'unknown')"

# -----------------------------------------------------------------------------
# TAILSCALE FIRST (for immediate SSH access)
# -----------------------------------------------------------------------------

%{ if enable_tailscale ~}
echo ">>> Installing Tailscale (priority)..."

# Install Tailscale using official package repository (more secure than curl|sh)
# Reference: https://tailscale.com/kb/1052/install-amazon-linux-2023
dnf config-manager --add-repo https://pkgs.tailscale.com/stable/amazon-linux/2023/tailscale.repo
dnf install -y tailscale

# Start the service
systemctl enable tailscaled
systemctl start tailscaled

# Wait for service to be ready
sleep 3
echo ">>> Tailscaled service status:"
systemctl status tailscaled --no-pager || true

%{ if tailscale_auth_key != "" ~}
echo ">>> Authenticating Tailscale..."
# Note: Auth key is not logged for security

# Authenticate with Tailscale
tailscale up \
  --authkey="${tailscale_auth_key}" \
  --hostname="${tailscale_hostname}" \
  --ssh \
  --accept-routes \
  --accept-dns=false

echo ">>> Tailscale authentication complete"
echo ">>> Tailscale status:"
tailscale status || true
tailscale ip || true
%{ else ~}
echo ">>> WARNING: No Tailscale auth key provided!"
echo ">>> Run manually: sudo tailscale up --ssh"
%{ endif ~}
%{ endif ~}

echo ">>> Tailscale setup complete. SSH available at: ${tailscale_hostname}"

# -----------------------------------------------------------------------------
# SWAP SPACE (for low memory instances)
# -----------------------------------------------------------------------------

# echo ">>> Creating 2GB swap space..."
# if [ ! -f /swapfile ]; then
#   fallocate -l 2G /swapfile
#   chmod 600 /swapfile
#   mkswap /swapfile
#   swapon /swapfile
#   echo '/swapfile swap swap defaults 0 0' >> /etc/fstab
# fi
# free -h

# -----------------------------------------------------------------------------
# SYSTEM PACKAGES
# -----------------------------------------------------------------------------

echo ">>> Installing dependencies..."
dnf update -y
dnf install -y git curl

# -----------------------------------------------------------------------------
# SETUP COMPLETE
# -----------------------------------------------------------------------------

echo "=== OpenClaw Setup Completed: $(date) ==="
echo ""
echo "Next steps:"
echo "  1. Connect via: ssh ec2-user@${tailscale_hostname}"
echo "  2. Install OpenClaw: curl -fsSL https://openclaw.ai/install.sh | bash"
echo "  3. Run onboarding: openclaw onboard"

# Create a marker file to indicate successful setup
touch /var/log/openclaw-setup-complete
