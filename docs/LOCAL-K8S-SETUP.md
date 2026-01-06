# Local Kubernetes Cluster Setup Guide

This guide walks you through setting up a local Kubernetes cluster on Hyper-V for GitHub self-hosted runners.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Hyper-V Host (Windows Server)            │
│                    Windows Admin Center                      │
│                                                              │
│  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────┐ │
│  │   k3s-master    │  │   k3s-worker-1  │  │ k3s-worker-2 │ │
│  │   Ubuntu 22.04  │  │   Ubuntu 22.04  │  │ Ubuntu 22.04 │ │
│  │   Control Plane │  │   Runner Node   │  │ Runner Node  │ │
│  │   2 CPU / 4GB   │  │   4 CPU / 8GB   │  │ 4 CPU / 8GB  │ │
│  └─────────────────┘  └─────────────────┘  └──────────────┘ │
│           │                    │                  │          │
│           └────────────────────┼──────────────────┘          │
│                                │                             │
│                    ┌───────────▼───────────┐                 │
│                    │   Internal vSwitch    │                 │
│                    │   10.10.10.0/24       │                 │
│                    └───────────────────────┘                 │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

- Windows Server 2019/2022 or Windows 10/11 Pro with Hyper-V enabled
- Windows Admin Center installed
- At least 32GB RAM on host (16GB minimum)
- 200GB+ free disk space
- Internet connectivity

## Part 1: Hyper-V Network Setup

### Step 1.1: Create Internal Virtual Switch

Open **PowerShell as Administrator** on your Hyper-V host:

```powershell
# Create internal switch for k8s cluster
New-VMSwitch -Name "k8s-internal" -SwitchType Internal

# Get the interface index
$ifIndex = (Get-NetAdapter | Where-Object {$_.Name -like "*k8s-internal*"}).ifIndex

# Assign IP to host adapter (this becomes the gateway)
New-NetIPAddress -IPAddress 10.10.10.1 -PrefixLength 24 -InterfaceIndex $ifIndex

# Enable NAT for internet access from VMs
New-NetNat -Name "k8s-nat" -InternalIPInterfaceAddressPrefix 10.10.10.0/24
```

### Step 1.2: Configure DNS Forwarding (Optional but Recommended)

```powershell
# If you have DNS issues, add a DNS forwarder
# Or configure your router/DNS server to resolve the VM hostnames
```

## Part 2: Create Ubuntu VMs

### Step 2.1: Download Ubuntu Server ISO

Download Ubuntu Server 22.04 LTS from: https://ubuntu.com/download/server

Save to: `C:\ISOs\ubuntu-22.04-live-server-amd64.iso`

### Step 2.2: Create VMs using PowerShell

Run the provided script or execute manually:

```powershell
# Variables
$VMPath = "C:\VMs"
$ISOPath = "C:\ISOs\ubuntu-22.04-live-server-amd64.iso"
$SwitchName = "k8s-internal"

# Create Master Node
New-VM -Name "k3s-master" -MemoryStartupBytes 4GB -Generation 2 -Path $VMPath -NewVHDPath "$VMPath\k3s-master\disk.vhdx" -NewVHDSizeBytes 50GB -SwitchName $SwitchName
Set-VMProcessor -VMName "k3s-master" -Count 2
Set-VMFirmware -VMName "k3s-master" -EnableSecureBoot Off
Add-VMDvdDrive -VMName "k3s-master" -Path $ISOPath
Set-VMFirmware -VMName "k3s-master" -FirstBootDevice (Get-VMDvdDrive -VMName "k3s-master")

# Create Worker Node 1
New-VM -Name "k3s-worker-1" -MemoryStartupBytes 8GB -Generation 2 -Path $VMPath -NewVHDPath "$VMPath\k3s-worker-1\disk.vhdx" -NewVHDSizeBytes 100GB -SwitchName $SwitchName
Set-VMProcessor -VMName "k3s-worker-1" -Count 4
Set-VMFirmware -VMName "k3s-worker-1" -EnableSecureBoot Off
Add-VMDvdDrive -VMName "k3s-worker-1" -Path $ISOPath
Set-VMFirmware -VMName "k3s-worker-1" -FirstBootDevice (Get-VMDvdDrive -VMName "k3s-worker-1")

# Create Worker Node 2 (Optional - for redundancy)
New-VM -Name "k3s-worker-2" -MemoryStartupBytes 8GB -Generation 2 -Path $VMPath -NewVHDPath "$VMPath\k3s-worker-2\disk.vhdx" -NewVHDSizeBytes 100GB -SwitchName $SwitchName
Set-VMProcessor -VMName "k3s-worker-2" -Count 4
Set-VMFirmware -VMName "k3s-worker-2" -EnableSecureBoot Off
Add-VMDvdDrive -VMName "k3s-worker-2" -Path $ISOPath
Set-VMFirmware -VMName "k3s-worker-2" -FirstBootDevice (Get-VMDvdDrive -VMName "k3s-worker-2")

# Start VMs
Start-VM -Name "k3s-master"
Start-VM -Name "k3s-worker-1"
Start-VM -Name "k3s-worker-2"
```

### Step 2.3: Install Ubuntu on Each VM

Connect to each VM via Hyper-V Manager or Windows Admin Center and complete Ubuntu installation:

1. Select language and keyboard
2. Choose "Ubuntu Server" (not minimized)
3. Network configuration - set static IPs:
   - **k3s-master**: 10.10.10.10/24, gateway 10.10.10.1, DNS 8.8.8.8
   - **k3s-worker-1**: 10.10.10.11/24, gateway 10.10.10.1, DNS 8.8.8.8
   - **k3s-worker-2**: 10.10.10.12/24, gateway 10.10.10.1, DNS 8.8.8.8
4. Configure storage (use entire disk)
5. Set username: `k8sadmin` (or your preference)
6. Set hostname to match VM name
7. Enable OpenSSH server
8. Skip snaps installation
9. Complete installation and reboot

### Step 2.4: Post-Installation Configuration

SSH into each VM and run:

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install required packages
sudo apt install -y curl wget git apt-transport-https ca-certificates gnupg lsb-release

# Disable swap (required for Kubernetes)
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab

# Load required kernel modules
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# Set sysctl params
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system

# Set up hosts file (run on ALL nodes)
echo "10.10.10.10 k3s-master" | sudo tee -a /etc/hosts
echo "10.10.10.11 k3s-worker-1" | sudo tee -a /etc/hosts
echo "10.10.10.12 k3s-worker-2" | sudo tee -a /etc/hosts

# Reboot
sudo reboot
```

## Part 3: Install k3s Cluster

### Step 3.1: Install k3s on Master Node

SSH into **k3s-master** (10.10.10.10):

```bash
# Install k3s server
curl -sfL https://get.k3s.io | sh -s - server \
    --write-kubeconfig-mode 644 \
    --disable traefik \
    --node-name k3s-master

# Wait for k3s to start
sudo systemctl status k3s

# Get node token (needed for workers)
sudo cat /var/lib/rancher/k3s/server/node-token

# Verify cluster
kubectl get nodes
```

Save the node token - you'll need it for worker nodes.

### Step 3.2: Install k3s on Worker Nodes

SSH into each worker node and run:

```bash
# Replace K3S_TOKEN with the token from master
# Replace K3S_URL with master's IP

curl -sfL https://get.k3s.io | K3S_URL=https://10.10.10.10:6443 K3S_TOKEN="YOUR_TOKEN_HERE" sh -s - agent \
    --node-name $(hostname)
```

### Step 3.3: Verify Cluster

Back on the master node:

```bash
kubectl get nodes
# Should show:
# NAME           STATUS   ROLES                  AGE   VERSION
# k3s-master     Ready    control-plane,master   5m    v1.28.x
# k3s-worker-1   Ready    <none>                 2m    v1.28.x
# k3s-worker-2   Ready    <none>                 1m    v1.28.x
```

### Step 3.4: Copy Kubeconfig to Your Workstation

On your local machine (Linux/Mac/WSL):

```bash
# Create .kube directory
mkdir -p ~/.kube

# Copy kubeconfig from master (adjust path as needed)
scp k8sadmin@10.10.10.10:/etc/rancher/k3s/k3s.yaml ~/.kube/config-local

# Update the server address in the config
sed -i 's/127.0.0.1/10.10.10.10/g' ~/.kube/config-local

# Use this config
export KUBECONFIG=~/.kube/config-local

# Test
kubectl get nodes
```

## Part 4: Install GitHub Actions Runner Controller

### Step 4.1: Install Helm (on master or your workstation)

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

### Step 4.2: Install cert-manager

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# Wait for cert-manager to be ready
kubectl wait --for=condition=Available --timeout=300s deployment/cert-manager -n cert-manager
kubectl wait --for=condition=Available --timeout=300s deployment/cert-manager-webhook -n cert-manager
kubectl wait --for=condition=Available --timeout=300s deployment/cert-manager-cainjector -n cert-manager
```

### Step 4.3: Create GitHub Personal Access Token

1. Go to GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)
2. Generate new token with scopes:
   - `repo` (full control)
   - `workflow`
   - `admin:org` (if using org runners)
3. Save the token securely

### Step 4.4: Install Actions Runner Controller

```bash
# Add Helm repo
helm repo add actions-runner-controller https://actions-runner-controller.github.io/actions-runner-controller
helm repo update

# Create namespace
kubectl create namespace actions-runner-system

# Install ARC with PAT authentication
helm install arc actions-runner-controller/actions-runner-controller \
    --namespace actions-runner-system \
    --set authSecret.create=true \
    --set authSecret.github_token="YOUR_GITHUB_PAT_HERE" \
    --wait

# Verify installation
kubectl get pods -n actions-runner-system
```

### Step 4.5: Deploy Runner Deployment

```bash
# Create runners namespace
kubectl create namespace github-runners

# Apply runner deployment
kubectl apply -f - <<EOF
apiVersion: actions.summerwind.dev/v1alpha1
kind: RunnerDeployment
metadata:
  name: infrastructure-runners
  namespace: github-runners
spec:
  replicas: 2
  template:
    spec:
      repository: YOUR_ORG/infrastructure-automation
      labels:
        - self-hosted
        - linux
        - local
        - infrastructure
      resources:
        requests:
          cpu: "1"
          memory: "2Gi"
        limits:
          cpu: "2"
          memory: "4Gi"
---
apiVersion: actions.summerwind.dev/v1alpha1
kind: HorizontalRunnerAutoscaler
metadata:
  name: infrastructure-runners-autoscaler
  namespace: github-runners
spec:
  scaleTargetRef:
    name: infrastructure-runners
  minReplicas: 1
  maxReplicas: 5
  metrics:
    - type: PercentageRunnersBusy
      scaleUpThreshold: '0.75'
      scaleDownThreshold: '0.25'
      scaleUpFactor: '2'
      scaleDownFactor: '0.5'
EOF

# Check runners
kubectl get runners -n github-runners
kubectl get pods -n github-runners
```

### Step 4.6: Verify Runners in GitHub

1. Go to your repository → Settings → Actions → Runners
2. You should see your self-hosted runners listed as "Idle"

## Part 5: Install Required Tools on Runner Image

The default runner image needs additional tools. Create a custom runner image:

### Step 5.1: Create Custom Dockerfile

See `infrastructure/local-runners/docker/Dockerfile` in this repository.

### Step 5.2: Build and Push to Local Registry (Optional)

If you want custom tools, set up a local registry:

```bash
# On master node, deploy local registry
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: registry
  namespace: kube-system
  labels:
    app: registry
spec:
  containers:
  - name: registry
    image: registry:2
    ports:
    - containerPort: 5000
---
apiVersion: v1
kind: Service
metadata:
  name: registry
  namespace: kube-system
spec:
  selector:
    app: registry
  ports:
  - port: 5000
    targetPort: 5000
EOF
```

## Troubleshooting

### Runners not appearing in GitHub
```bash
# Check ARC controller logs
kubectl logs -n actions-runner-system deployment/arc-actions-runner-controller

# Check runner pod logs
kubectl logs -n github-runners -l app=runner
```

### Network issues from VMs
```bash
# Test DNS
nslookup github.com

# Test connectivity
curl -I https://github.com

# Check NAT on Hyper-V host
Get-NetNat
```

### k3s issues
```bash
# Check k3s logs
sudo journalctl -u k3s -f

# Restart k3s
sudo systemctl restart k3s
```

## Next Steps

1. Update GitHub Actions workflows to use `runs-on: [self-hosted, linux, local]`
2. Configure secrets in GitHub repository for Azure access
3. Test with a sample infrastructure request

See `infrastructure/local-runners/deploy-local-arc.sh` for automated deployment.
