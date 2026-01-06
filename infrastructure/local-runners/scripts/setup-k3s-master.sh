#!/bin/bash
#
# k3s Master Node Setup Script
# Run this on the master node (k3s-master / 10.10.10.10)
#

set -e

echo "============================================"
echo "  k3s Master Node Setup"
echo "============================================"
echo ""

# Check if running as root or with sudo
if [ "$EUID" -ne 0 ]; then
    echo "Please run with sudo: sudo $0"
    exit 1
fi

MASTER_IP="10.10.10.10"
HOSTNAME=$(hostname)

echo "[1/6] Configuring system prerequisites..."

# Update system
apt update && apt upgrade -y

# Install required packages
apt install -y curl wget git apt-transport-https ca-certificates gnupg lsb-release jq

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

echo "[2/6] Configuring hosts file..."

# Add hosts entries
grep -q "k3s-master" /etc/hosts || echo "10.10.10.10 k3s-master" >> /etc/hosts
grep -q "k3s-worker-1" /etc/hosts || echo "10.10.10.11 k3s-worker-1" >> /etc/hosts
grep -q "k3s-worker-2" /etc/hosts || echo "10.10.10.12 k3s-worker-2" >> /etc/hosts

echo "[3/6] Installing k3s server..."

# Install k3s
curl -sfL https://get.k3s.io | sh -s - server \
    --write-kubeconfig-mode 644 \
    --disable traefik \
    --node-ip $MASTER_IP \
    --node-name $HOSTNAME \
    --tls-san $MASTER_IP \
    --tls-san k3s-master

# Wait for k3s to be ready
echo "Waiting for k3s to start..."
sleep 10

# Check status
systemctl status k3s --no-pager

echo "[4/6] Installing Helm..."

curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

echo "[5/6] Retrieving cluster information..."

# Get node token
NODE_TOKEN=$(cat /var/lib/rancher/k3s/server/node-token)

echo ""
echo "============================================"
echo "  Master Node Setup Complete!"
echo "============================================"
echo ""
echo "Cluster Status:"
kubectl get nodes
echo ""
echo "============================================"
echo "  IMPORTANT: Save this information!"
echo "============================================"
echo ""
echo "K3S_URL=https://$MASTER_IP:6443"
echo ""
echo "K3S_TOKEN=$NODE_TOKEN"
echo ""
echo "============================================"
echo ""
echo "Run this on each worker node:"
echo ""
echo "curl -sfL https://get.k3s.io | K3S_URL=https://$MASTER_IP:6443 K3S_TOKEN=\"$NODE_TOKEN\" sh -s - agent --node-name \$(hostname)"
echo ""

# Save token to file
echo "$NODE_TOKEN" > /root/k3s-node-token.txt
chmod 600 /root/k3s-node-token.txt
echo "Token also saved to: /root/k3s-node-token.txt"

echo ""
echo "[6/6] Creating kubeconfig for remote access..."

# Create a kubeconfig for external access
KUBECONFIG_EXTERNAL="/etc/rancher/k3s/k3s-external.yaml"
cp /etc/rancher/k3s/k3s.yaml $KUBECONFIG_EXTERNAL
sed -i "s/127.0.0.1/$MASTER_IP/g" $KUBECONFIG_EXTERNAL
chmod 644 $KUBECONFIG_EXTERNAL

echo "External kubeconfig saved to: $KUBECONFIG_EXTERNAL"
echo ""
echo "To use from your workstation:"
echo "  scp $USER@$MASTER_IP:$KUBECONFIG_EXTERNAL ~/.kube/config-local"
echo "  export KUBECONFIG=~/.kube/config-local"
echo ""
