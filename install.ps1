# install.ps1 - BeamMP Server Installation Script for Windows VPS
# Run as Administrator

param(
    [string]$InstallPath = "C:\BeamMP-Server",
    [string]$ServerVersion = "latest"
)

Write-Host "=== BeamMP Server Windows VPS Installation ===" -ForegroundColor Green

# Check if running as Administrator
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "This script must be run as Administrator!" -ForegroundColor Red
    exit 1
}

# Create installation directory
Write-Host "Creating installation directory: $InstallPath" -ForegroundColor Yellow
if (!(Test-Path -Path $InstallPath)) {
    New-Item -ItemType Directory -Path $InstallPath -Force
}

# Create subdirectories
$subdirs = @("logs", "mods", "plugins", "config")
foreach ($dir in $subdirs) {
    $fullPath = Join-Path -Path $InstallPath -ChildPath $dir
    if (!(Test-Path -Path $fullPath)) {
        New-Item -ItemType Directory -Path $fullPath -Force
        Write-Host "Created directory: $fullPath" -ForegroundColor Gray
    }
}

# Download BeamMP Server
Write-Host "Downloading BeamMP Server..." -ForegroundColor Yellow
$downloadUrl = "https://github.com/BeamMP/BeamMP-Server/releases/latest/download/BeamMP-Server.exe"
$serverExePath = Join-Path -Path $InstallPath -ChildPath "BeamMP-Server.exe"

try {
    Invoke-WebRequest -Uri $downloadUrl -OutFile $serverExePath -UseBasicParsing
    Write-Host "BeamMP Server downloaded successfully" -ForegroundColor Green
} catch {
    Write-Host "Failed to download BeamMP Server: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Download Visual C++ Redistributable (required for BeamMP)
Write-Host "Downloading Visual C++ Redistributable..." -ForegroundColor Yellow
$vcRedistUrl = "https://aka.ms/vs/17/release/vc_redist.x64.exe"
$vcRedistPath = Join-Path -Path $env:TEMP -ChildPath "vc_redist.x64.exe"

try {
    Invoke-WebRequest -Uri $vcRedistUrl -OutFile $vcRedistPath -UseBasicParsing
    Write-Host "Installing Visual C++ Redistributable..." -ForegroundColor Yellow
    Start-Process -FilePath $vcRedistPath -ArgumentList "/quiet" -Wait
    Remove-Item $vcRedistPath -Force
    Write-Host "Visual C++ Redistributable installed" -ForegroundColor Green
} catch {
    Write-Host "Warning: Failed to install Visual C++ Redistributable: $($_.Exception.Message)" -ForegroundColor Orange
}

# Copy configuration files
Write-Host "Setting up configuration files..." -ForegroundColor Yellow
$configSource = Join-Path -Path (Get-Location) -ChildPath "config"
$configDest = Join-Path -Path $InstallPath -ChildPath "config"

if (Test-Path -Path $configSource) {
    Copy-Item -Path "$configSource\*" -Destination $configDest -Recurse -Force
    Write-Host "Configuration files copied" -ForegroundColor Green
} else {
    Write-Host "No configuration files found in ./config - you'll need to create ServerConfig.toml manually" -ForegroundColor Orange
}

# Configure Windows Firewall
Write-Host "Configuring Windows Firewall..." -ForegroundColor Yellow
try {
    # Remove existing rules if they exist
    Remove-NetFirewallRule -DisplayName "BeamMP Server TCP" -ErrorAction SilentlyContinue
    Remove-NetFirewallRule -DisplayName "BeamMP Server UDP" -ErrorAction SilentlyContinue
    
    # Add new firewall rules
    New-NetFirewallRule -DisplayName "BeamMP Server TCP" -Direction Inbound -Protocol TCP -LocalPort 30814 -Action Allow
    New-NetFirewallRule -DisplayName "BeamMP Server UDP" -Direction Inbound -Protocol UDP -LocalPort 30814 -Action Allow
    Write-Host "Firewall rules configured for port 30814" -ForegroundColor Green
} catch {
    Write-Host "Warning: Failed to configure firewall: $($_.Exception.Message)" -ForegroundColor Orange
}

# Create startup script
Write-Host "Creating startup script..." -ForegroundColor Yellow
$startupScript = @"
# start-server.ps1 - BeamMP Server Startup Script
param(
    [string]`$ConfigFile = "config\ServerConfig.toml"
)

Set-Location "$InstallPath"

Write-Host "=== Starting BeamMP Server ===" -ForegroundColor Green
Write-Host "Server Path: $InstallPath" -ForegroundColor Gray
Write-Host "Config File: `$ConfigFile" -ForegroundColor Gray
Write-Host "Press Ctrl+C to stop the server" -ForegroundColor Yellow
Write-Host ""

# Start the server
try {
    & ".\BeamMP-Server.exe" --config "`$ConfigFile"
} catch {
    Write-Host "Error starting server: `$(`$_.Exception.Message)" -ForegroundColor Red
    Write-Host "Check the logs in the logs directory" -ForegroundColor Orange
    pause
}
"@

$startupScriptPath = Join-Path -Path $InstallPath -ChildPath "start-server.ps1"
$startupScript | Out-File -FilePath $startupScriptPath -Encoding UTF8

# Create update script
$updateScript = @"
# update-server.ps1 - BeamMP Server Update Script
Write-Host "=== Updating BeamMP Server ===" -ForegroundColor Green

Set-Location "$InstallPath"

# Stop server if running
Get-Process -Name "BeamMP-Server" -ErrorAction SilentlyContinue | Stop-Process -Force

# Backup current server
if (Test-Path "BeamMP-Server.exe") {
    Copy-Item "BeamMP-Server.exe" "BeamMP-Server.exe.bak" -Force
    Write-Host "Current server backed up" -ForegroundColor Gray
}

# Download latest version
Write-Host "Downloading latest BeamMP Server..." -ForegroundColor Yellow
try {
    Invoke-WebRequest -Uri "https://github.com/BeamMP/BeamMP-Server/releases/latest/download/BeamMP-Server.exe" -OutFile "BeamMP-Server.exe" -UseBasicParsing
    Write-Host "Server updated successfully!" -ForegroundColor Green
    Write-Host "You can now start the server with: .\start-server.ps1" -ForegroundColor Yellow
} catch {
    Write-Host "Update failed: `$(`$_.Exception.Message)" -ForegroundColor Red
    if (Test-Path "BeamMP-Server.exe.bak") {
        Move-Item "BeamMP-Server.exe.bak" "BeamMP-Server.exe" -Force
        Write-Host "Restored backup server" -ForegroundColor Orange
    }
}
"@

$updateScriptPath = Join-Path -Path $InstallPath -ChildPath "update-server.ps1"
$updateScript | Out-File -FilePath $updateScriptPath -Encoding UTF8

# Create default server configuration if not exists
$configPath = Join-Path -Path $InstallPath -ChildPath "config\ServerConfig.toml"
if (!(Test-Path -Path $configPath)) {
    Write-Host "Creating default server configuration..." -ForegroundColor Yellow
    
    $defaultConfig = @"
[General]
Name = "My BeamMP Server"
Port = 30814
Cars = 8
Max_Cars = 8
Max_Players = 8
Lan = false
Public = true
Debug = false
Private = false

[Misc]
SendErrors = true
SendErrorsShowPlayerName = true
HideUpdateMessages = false
UpdateIntervalMs = 3000
"@
    
    New-Item -ItemType Directory -Path (Split-Path $configPath -Parent) -Force -ErrorAction SilentlyContinue
    $defaultConfig | Out-File -FilePath $configPath -Encoding UTF8
    Write-Host "Default configuration created at: $configPath" -ForegroundColor Green
    Write-Host "IMPORTANT: You need to add your AuthKey to the configuration!" -ForegroundColor Red
}

# Installation complete
Write-Host ""
Write-Host "=== Installation Complete! ===" -ForegroundColor Green
Write-Host ""
Write-Host "Installation Path: $InstallPath" -ForegroundColor Gray
Write-Host "Configuration: $configPath" -ForegroundColor Gray
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "1. Get your AuthKey from https://beammp.com/keymaster" -ForegroundColor White
Write-Host "2. Edit the ServerConfig.toml file and add your AuthKey" -ForegroundColor White
Write-Host "3. Run: cd '$InstallPath' && .\start-server.ps1" -ForegroundColor White
Write-Host ""
Write-Host "Server Commands:" -ForegroundColor Yellow
Write-Host "  Start:  .\start-server.ps1" -ForegroundColor White
Write-Host "  Update: .\update-server.ps1" -ForegroundColor White
Write-Host ""

Write-Host "Press any key to continue..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
