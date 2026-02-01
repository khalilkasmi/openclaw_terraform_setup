#!/bin/bash
set -euo pipefail

exec > >(tee /var/log/openclaw-setup.log) 2>&1
echo "=== OpenClaw Setup Started: $(date) ==="

# -----------------------------------------------------------------------------
# TAILSCALE FIRST (for immediate SSH access)
# -----------------------------------------------------------------------------

%{ if enable_tailscale ~}
echo ">>> Installing Tailscale (priority)..."

# Install Tailscale
curl -fsSL https://tailscale.com/install.sh | sh

# Start the service
systemctl enable tailscaled
systemctl start tailscaled

# Wait for service to be ready
sleep 3
echo ">>> Tailscaled service status:"
systemctl status tailscaled --no-pager || true

%{ if tailscale_auth_key != "" ~}
echo ">>> Authenticating Tailscale..."
echo ">>> Using auth key: ${substr(tailscale_auth_key, 0, 15)}..."

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

# # -----------------------------------------------------------------------------
# # OPENCLAW (official installation)
# # -----------------------------------------------------------------------------

# echo ">>> Installing OpenClaw via official installer..."

# sudo -u ec2-user bash <<'INSTALL_SCRIPT'
# set -e
# cd ~

# # Official OpenClaw installation
# curl -fsSL https://openclaw.ai/install.sh | bash

# # Source the updated PATH
# export PATH="$HOME/.local/bin:$PATH"

# # Verify installation
# echo ">>> OpenClaw version:"
# openclaw --version || echo "OpenClaw may need 'openclaw onboard' to complete setup"
# INSTALL_SCRIPT

# echo ">>> OpenClaw installed for ec2-user"

# # -----------------------------------------------------------------------------
# # API KEYS
# # -----------------------------------------------------------------------------

# %{ if anthropic_api_key != "" ~}
# echo ">>> Configuring Anthropic API key..."
# sudo -u ec2-user bash -c 'grep -q ANTHROPIC_API_KEY ~/.bashrc || echo "export ANTHROPIC_API_KEY=\"${anthropic_api_key}\"" >> ~/.bashrc'
# %{ endif ~}

# %{ if openai_api_key != "" ~}
# echo ">>> Configuring OpenAI API key..."
# sudo -u ec2-user bash -c 'grep -q OPENAI_API_KEY ~/.bashrc || echo "export OPENAI_API_KEY=\"${openai_api_key}\"" >> ~/.bashrc'
# %{ endif ~}

# # -----------------------------------------------------------------------------
# # DONE
# # -----------------------------------------------------------------------------

# echo "=== OpenClaw Setup Completed: $(date) ==="
# echo ""
# echo "Connect via: ssh ec2-user@${tailscale_hostname}"
# echo "Then run: openclaw onboard"
