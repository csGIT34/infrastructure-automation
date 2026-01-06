#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Creates Hyper-V VMs for a k3s Kubernetes cluster.

.DESCRIPTION
    This script creates the virtual network and VMs needed for a local k3s cluster
    to run GitHub Actions self-hosted runners.

.PARAMETER VMPath
    Path where VM files will be stored. Default: C:\VMs

.PARAMETER ISOPath
    Path to Ubuntu Server 22.04 ISO. Default: C:\ISOs\ubuntu-22.04-live-server-amd64.iso

.PARAMETER WorkerCount
    Number of worker nodes to create. Default: 2

.PARAMETER SkipNetworkSetup
    Skip virtual switch and NAT creation if already configured.

.EXAMPLE
    .\Create-HyperVCluster.ps1 -VMPath "D:\VMs" -WorkerCount 2
#>

param(
    [string]$VMPath = "C:\VMs",
    [string]$ISOPath = "C:\ISOs\ubuntu-22.04-live-server-amd64.iso",
    [int]$WorkerCount = 2,
    [switch]$SkipNetworkSetup
)

$ErrorActionPreference = "Stop"

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Hyper-V k3s Cluster Setup Script" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Check prerequisites
Write-Host "[1/6] Checking prerequisites..." -ForegroundColor Yellow

if (-not (Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V).State -eq "Enabled") {
    Write-Error "Hyper-V is not enabled. Please enable it first:
    Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All"
    exit 1
}

if (-not (Test-Path $ISOPath)) {
    Write-Error "Ubuntu ISO not found at: $ISOPath
    Download from: https://ubuntu.com/download/server"
    exit 1
}

# Create VM directory
if (-not (Test-Path $VMPath)) {
    New-Item -ItemType Directory -Path $VMPath -Force | Out-Null
    Write-Host "  Created VM directory: $VMPath" -ForegroundColor Green
}

# Network Setup
Write-Host "[2/6] Setting up virtual network..." -ForegroundColor Yellow

$SwitchName = "k8s-internal"

if (-not $SkipNetworkSetup) {
    # Check if switch already exists
    $existingSwitch = Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue

    if ($existingSwitch) {
        Write-Host "  Virtual switch '$SwitchName' already exists" -ForegroundColor Yellow
    } else {
        # Create internal switch
        New-VMSwitch -Name $SwitchName -SwitchType Internal | Out-Null
        Write-Host "  Created virtual switch: $SwitchName" -ForegroundColor Green

        # Wait for adapter to be created
        Start-Sleep -Seconds 2

        # Get adapter and configure IP
        $adapter = Get-NetAdapter | Where-Object { $_.Name -like "*$SwitchName*" }
        if ($adapter) {
            New-NetIPAddress -IPAddress 10.10.10.1 -PrefixLength 24 -InterfaceIndex $adapter.ifIndex -ErrorAction SilentlyContinue | Out-Null
            Write-Host "  Configured host IP: 10.10.10.1/24" -ForegroundColor Green
        }
    }

    # Check/Create NAT
    $existingNat = Get-NetNat -Name "k8s-nat" -ErrorAction SilentlyContinue
    if ($existingNat) {
        Write-Host "  NAT 'k8s-nat' already exists" -ForegroundColor Yellow
    } else {
        New-NetNat -Name "k8s-nat" -InternalIPInterfaceAddressPrefix 10.10.10.0/24 | Out-Null
        Write-Host "  Created NAT for internet access" -ForegroundColor Green
    }
} else {
    Write-Host "  Skipping network setup (--SkipNetworkSetup specified)" -ForegroundColor Yellow
}

# VM Configurations
$VMs = @(
    @{
        Name = "k3s-master"
        CPU = 2
        MemoryGB = 4
        DiskGB = 50
        IP = "10.10.10.10"
        Role = "master"
    }
)

for ($i = 1; $i -le $WorkerCount; $i++) {
    $VMs += @{
        Name = "k3s-worker-$i"
        CPU = 4
        MemoryGB = 8
        DiskGB = 100
        IP = "10.10.10.$($10 + $i)"
        Role = "worker"
    }
}

# Create VMs
Write-Host "[3/6] Creating virtual machines..." -ForegroundColor Yellow

foreach ($vm in $VMs) {
    $vmName = $vm.Name

    # Check if VM already exists
    if (Get-VM -Name $vmName -ErrorAction SilentlyContinue) {
        Write-Host "  VM '$vmName' already exists - skipping" -ForegroundColor Yellow
        continue
    }

    $vmPath = Join-Path $VMPath $vmName
    $vhdPath = Join-Path $vmPath "disk.vhdx"

    Write-Host "  Creating $vmName ($($vm.Role))..." -ForegroundColor White

    # Create VM
    New-VM -Name $vmName `
           -MemoryStartupBytes ($vm.MemoryGB * 1GB) `
           -Generation 2 `
           -Path $VMPath `
           -NewVHDPath $vhdPath `
           -NewVHDSizeBytes ($vm.DiskGB * 1GB) `
           -SwitchName $SwitchName | Out-Null

    # Configure VM
    Set-VMProcessor -VMName $vmName -Count $vm.CPU
    Set-VMFirmware -VMName $vmName -EnableSecureBoot Off

    # Add DVD drive with ISO
    Add-VMDvdDrive -VMName $vmName -Path $ISOPath
    $dvd = Get-VMDvdDrive -VMName $vmName
    Set-VMFirmware -VMName $vmName -FirstBootDevice $dvd

    # Enable guest services for easier file transfer
    Enable-VMIntegrationService -VMName $vmName -Name "Guest Service Interface"

    Write-Host "    CPU: $($vm.CPU), RAM: $($vm.MemoryGB)GB, Disk: $($vm.DiskGB)GB" -ForegroundColor DarkGray
    Write-Host "    IP: $($vm.IP)" -ForegroundColor DarkGray
}

Write-Host "  All VMs created successfully" -ForegroundColor Green

# Generate cloud-init configs (for reference)
Write-Host "[4/6] Generating configuration files..." -ForegroundColor Yellow

$configPath = Join-Path $VMPath "configs"
New-Item -ItemType Directory -Path $configPath -Force | Out-Null

foreach ($vm in $VMs) {
    $networkConfig = @"
# Network configuration for $($vm.Name)
# Apply this during Ubuntu installation or via /etc/netplan/

network:
  version: 2
  ethernets:
    eth0:
      addresses:
        - $($vm.IP)/24
      gateway4: 10.10.10.1
      nameservers:
        addresses:
          - 8.8.8.8
          - 8.8.4.4
"@

    $networkConfig | Out-File -FilePath (Join-Path $configPath "$($vm.Name)-network.yaml") -Encoding UTF8
}

Write-Host "  Network configs saved to: $configPath" -ForegroundColor Green

# Print summary
Write-Host "[5/6] VM Summary" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Name             Role      CPU   RAM    Disk   IP Address" -ForegroundColor White
Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray

foreach ($vm in $VMs) {
    $role = $vm.Role.PadRight(8)
    $cpu = "$($vm.CPU)".PadRight(4)
    $ram = "$($vm.MemoryGB)GB".PadRight(5)
    $disk = "$($vm.DiskGB)GB".PadRight(5)
    Write-Host "  $($vm.Name.PadRight(16)) $role  $cpu  $ram  $disk  $($vm.IP)" -ForegroundColor Gray
}

Write-Host ""

# Start VMs
Write-Host "[6/6] Starting VMs..." -ForegroundColor Yellow

foreach ($vm in $VMs) {
    $vmState = (Get-VM -Name $vm.Name).State
    if ($vmState -ne "Running") {
        Start-VM -Name $vm.Name
        Write-Host "  Started $($vm.Name)" -ForegroundColor Green
    } else {
        Write-Host "  $($vm.Name) is already running" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Setup Complete!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "  1. Connect to each VM via Hyper-V Manager" -ForegroundColor White
Write-Host "  2. Complete Ubuntu installation with these IPs:" -ForegroundColor White
foreach ($vm in $VMs) {
    Write-Host "     - $($vm.Name): $($vm.IP)/24, gateway 10.10.10.1" -ForegroundColor Gray
}
Write-Host "  3. After installation, run the k3s setup scripts" -ForegroundColor White
Write-Host ""
Write-Host "Network configs saved to: $configPath" -ForegroundColor DarkGray
Write-Host ""
