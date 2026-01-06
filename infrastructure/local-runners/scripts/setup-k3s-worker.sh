#!/bin/bash
#
# k3s Worker Node Setup Script
# Run this on each worker node
#

set -e

echo "============================================"
echo "  k3s Worker Node Setup"
echo "============================================"
echo ""

# Check if running as root or with sudo
if [ "$EUID" -ne 0 ]; then
    echo "Please run with sudo: sudo $0 <K3S_TOKEN>"
    exit 1
fi

# Check for token argument
if [ -z "$1" ]; then
    echo "Usage: sudo $0 <K3S_TOKEN>"
    echo ""
    echo "Get the token from the master node:"
    echo "  cat /var/lib/rancher/k3s/server/node-token"
    exit 1
fi

K3S_TOKEN="$1"
MASTER_IP="10.10.10.10"
HOSTNAME=$(hostname)

echo "[1/5] Configuring system prerequisites..."

# Update system
apt update && apt upgrade -y

# Install required packages
apt install -y curl wget git apt-transport-https ca-certificates gnupg lsb-release

# Disable swap
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

# Load kernel modules
cat <<EOF > /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

# Sysctl settings
cat <<EOF > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system

echo "[2/5] Configuring hosts file..."

# Add hosts entries
grep -q "k3s-master" /etc/hosts || echo "10.10.10.10 k3s-master" >> /etc/hosts
grep -q "k3s-worker-1" /etc/hosts || echo "10.10.10.11 k3s-worker-1" >> /etc/hosts
grep -q "k3s-worker-2" /etc/hosts || echo "10.10.10.12 k3s-worker-2" >> /etc/hosts

echo "[3/5] Installing k3s agent..."

# Install k3s agent
curl -sfL https://get.k3s.io | K3S_URL=https://$MASTER_IP:6443 K3S_TOKEN="$K3S_TOKEN" sh -s - agent \
    --node-name $HOSTNAME

# Wait for k3s-agent to start
echo "Waiting for k3s-agent to start..."
sleep 5

echo "[4/5] Checking status..."

systemctl status k3s-agent --no-pager

echo "[5/5] Installing additional tools for runners..."

# Install Docker (for container builds in workflows)
curl -fsSL https://get.docker.com | sh
usermod -aG docker $SUDO_USER 2>/dev/null || true

# Install common tools
apt install -y \
    python3 \
    python3-pip \
    python3-venv \
    unzip \
    jq

echo ""
echo "============================================"
echo "  Worker Node Setup Complete!"
echo "============================================"
echo ""
echo "Node: $HOSTNAME"
echo "Connected to master: $MASTER_IP"
echo ""
echo "Verify on master node with:"
echo "  kubectl get nodes"
echo ""
