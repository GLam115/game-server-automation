<#
.SYNOPSIS
    Provision a Windows machine with an idempotent approach using PowerShell and Chocolatey, including directory creation and auto-login configuration for Steam and Parsec.

.DESCRIPTION
    This script:
    - Checks if Chocolatey is installed and installs it if missing.
    - Installs or upgrades specified software packages using Chocolatey.
    - Creates local users if they do not exist.
    - Sets up the desired directory structure under C:\ES\Media\Games.
    - Configures Steam and Parsec to auto-launch at system startup.
    - Pins specified applications to the taskbar.
    - Installs uBlock Origin extension on Google Chrome and Firefox.
    - Enables uBlock Origin in incognito/private mode.
    - Clones a Git repository into the ES directory.

.NOTES
    Author: Your Name
    Date  : 2024-xx-xx
    Tested On: Windows 10 / Windows 11
#>

# ----------------------------------------------
# 1. HELPER FUNCTIONS
# ----------------------------------------------

function Write-Info {
    param([string]$message)
    Write-Host "[INFO] $message" -ForegroundColor Cyan
}

function Write-WarningMessage {
    param([string]$message)
    Write-Host "[WARNING] $message" -ForegroundColor Yellow
}

function Write-ErrorMessage {
    param([string]$message)
    Write-Host "[ERROR] $message" -ForegroundColor Red
    exit 1
}

# Function to check if the script is run as Administrator
function Test-Administrator {
    $currentUser = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Function to check if Chocolatey is installed
function Is-ChocolateyInstalled {
    return (Get-Command choco -ErrorAction SilentlyContinue) -ne $null
}

# Function to install Chocolatey if it's not installed
function Ensure-Chocolatey {
    if (-not (Is-ChocolateyInstalled)) {
        Write-Info "Chocolatey not found. Installing..."
        # Bypass execution policy for the current process
        Set-ExecutionPolicy Bypass -Scope Process -Force
        # Ensure TLS 1.2 is used
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        # Download and execute Chocolatey's installation script
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
        
        # Refresh environment variables for the current session
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Process")
        if (-not (Is-ChocolateyInstalled)) {
            Write-ErrorMessage "Chocolatey installation failed."
        } else {
            Write-Info "Chocolatey installed successfully."
        }
    } else {
        Write-Info "Chocolatey is already installed."
    }
}

# Function to ensure a Chocolatey package is installed or upgraded
function Ensure-ChocoPackageInstalled {
    param(
        [Parameter(Mandatory=$true)]
        [string]$PackageName,
        
        [switch]$ForceUpgrade  # Use to force upgrade even if installed
    )

    # Check if the package is already installed
    $installed = choco list --local-only | Where-Object { $_ -match "^(?:$PackageName)\s" }
    if (-not $installed) {
        Write-Info "Package '$PackageName' not installed. Installing via Chocolatey..."
        choco install $PackageName -y
    }
    elseif ($ForceUpgrade) {
        Write-Info "Forcing upgrade of '$PackageName'."
        choco upgrade $PackageName -y
    }
    else {
        Write-Info "Package '$PackageName' is already installed. Skipping."
    }
}

# Function to ensure a local user exists and is in the specified group
function Ensure-LocalUser {
    param(
        [Parameter(Mandatory=$true)]
        [string]$UserName,

        [Parameter(Mandatory=$true)]
        [string]$PasswordPlainText,

        [string]$FullName = "",
        [string]$Description = "",
        [string]$Group = "Users"  # Could be "Administrators" if needed
    )

    $user = Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue
    if ($null -eq $user) {
        Write-Info "User '$UserName' does not exist. Creating..."
        $securePass = ConvertTo-SecureString $PasswordPlainText -AsPlainText -Force
        New-LocalUser -Name $UserName -Password $securePass -FullName $FullName -Description $Description

        # Add user to the desired group
        Write-Info "Adding '$UserName' to '$Group' group."
        Add-LocalGroupMember -Group $Group -Member $UserName
    }
    else {
        Write-Info "User '$UserName' already exists. Ensuring group membership..."
        $isMember = Get-LocalGroupMember -Group $Group -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $UserName }
        if (-not $isMember) {
            Write-Info "Adding '$UserName' to '$Group' group."
            Add-LocalGroupMember -Group $Group -Member $UserName
        }
        else {
            Write-Info "User '$UserName' is already in group '$Group'. Skipping."
        }
    }
}

# Function to ensure a directory exists
function Ensure-Directory {
    param(
        [Parameter(Mandatory=$true)]
        [string]$DirectoryPath
    )

    if (-not (Test-Path -Path $DirectoryPath)) {
        Write-Info "Directory '$DirectoryPath' does not exist. Creating..."
        New-Item -ItemType Directory -Path $DirectoryPath -Force | Out-Null
    }
    else {
        Write-Info "Directory '$DirectoryPath' already exists. Skipping."
    }
}

# Function to pin applications to the taskbar
function Pin-AppToTaskbar {
    param (
        [Parameter(Mandatory = $true)]
        [string]$AppName
    )
    
    # Use Chocolatey to find the installation path
    $appPath = choco where $AppName 2>$null
    if (-not $appPath) {
        Write-WarningMessage "Could not find installation path for '$AppName'. Skipping pinning."
        return
    }

    if (!(Test-Path $appPath)) {
        Write-WarningMessage "Application path '$appPath' does not exist. Skipping pinning."
        return
    }

    try {
        $shell = New-Object -ComObject Shell.Application
        $folderPath = Split-Path -Parent $appPath
        $fileName = Split-Path -Leaf $appPath
        $folder = $shell.Namespace($folderPath)
        $item = $folder.ParseName($fileName)
        
        # Find the 'Pin to taskbar' verb
        $verbs = $item.Verbs() | Where-Object { $_.Name -match "Pin to Taskbar" }
        if ($verbs) {
            $verbs.DoIt()
            Write-Info "Pinned '$AppName' to taskbar successfully."
        }
        else {
            Write-WarningMessage "Could not find 'Pin to Taskbar' option for '$AppName'. Ensure the application supports pinning."
        }
    }
    catch {
        Write-WarningMessage "Failed to pin '$AppName' to taskbar. Error: $_"
    }
}

# Function to pin multiple applications to the taskbar
function Pin-AppsToTaskbar {
    param (
        [Parameter(Mandatory = $true)]
        [array]$Apps
    )

    foreach ($app in $Apps) {
        Pin-AppToTaskbar -AppName $app.Name
    }
}

# Function to install uBlock Origin on Chrome via policies
function Configure-ChromeUblockOrigin {
    $extensionID = "cjpalhdlnbpafiamejdnhcphjbkeiagm"
    $updateURL = "https://clients2.google.com/service/update2/crx"
    
    # Path for ExtensionInstallForcelist
    $regPath = "HKLM:\SOFTWARE\Policies\Google\Chrome\ExtensionInstallForcelist"
    if (-not (Test-Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
    }
    
    # Add uBlock Origin to ExtensionInstallForcelist
    $existing = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
    if (-not ($existing.PSObject.Properties.Name -contains $extensionID)) {
        $count = (Get-ChildItem -Path $regPath).Count
        Set-ItemProperty -Path $regPath -Name "$count" -Value "$extensionID;$updateURL"
        Write-Info "Added uBlock Origin to Chrome's ExtensionInstallForcelist."
    }
    else {
        Write-Info "uBlock Origin is already in Chrome's ExtensionInstallForcelist."
    }
    
    # Path for ExtensionAllowedIncognito
    $regPathIncognito = "HKLM:\SOFTWARE\Policies\Google\Chrome\ExtensionAllowedIncognito"
    if (-not (Test-Path $regPathIncognito)) {
        New-Item -Path $regPathIncognito -Force | Out-Null
    }
    
    # Add uBlock Origin to ExtensionAllowedIncognito
    $existingIncognito = Get-ItemProperty -Path $regPathIncognito -ErrorAction SilentlyContinue
    if (-not ($existingIncognito.PSObject.Properties.Name -contains $extensionID)) {
        $count = (Get-ChildItem -Path $regPathIncognito).Count
        Set-ItemProperty -Path $regPathIncognito -Name "$count" -Value "$extensionID"
        Write-Info "Allowed uBlock Origin to run in incognito mode."
    }
    else {
        Write-Info "uBlock Origin is already allowed in incognito mode."
    }
}

# Function to install uBlock Origin on Firefox via policies
function Configure-FirefoxUblockOrigin {
    $policyDir = "C:\Program Files\Mozilla Firefox\distribution"
    $policyFile = "policies.json"
    $policyPath = Join-Path -Path $policyDir -ChildPath $policyFile

    if (-not (Test-Path $policyDir)) {
        New-Item -Path $policyDir -ItemType Directory -Force | Out-Null
        Write-Info "Created Firefox policy directory at '$policyDir'."
    }

    if (-not (Test-Path $policyPath)) {
        $policies = @{
            "policies" = @{
                "Extensions" = @(
                    @{
                        "ID" = "uBlock0@raymondhill.net"
                        "UpdateURL" = "https://addons.mozilla.org/firefox/downloads/latest/uBlock-Origin/addon-477166-latest.xpi"
                    }
                )
                "Preferences" = @{
                    "extensions.ublock0.run_in_private_browsing" = $true
                }
            }
        }
        $policies | ConvertTo-Json -Depth 10 | Out-File -FilePath $policyPath -Encoding UTF8
        Write-Info "Created Firefox policies.json with uBlock Origin installation and private browsing configuration."
    }
    else {
        # Update policies.json if uBlock Origin is not present
        $policies = Get-Content -Path $policyPath | ConvertFrom-Json
        $extensionExists = $policies.policies.Extensions | Where-Object { $_.ID -eq "uBlock0@raymondhill.net" }
        if (-not $extensionExists) {
            $newExtension = @{
                "ID" = "uBlock0@raymondhill.net"
                "UpdateURL" = "https://addons.mozilla.org/firefox/downloads/latest/uBlock-Origin/addon-477166-latest.xpi"
            }
            $policies.policies.Extensions += $newExtension
            # Enable uBlock Origin in private browsing
            if (-not $policies.policies.Preferences) {
                $policies.policies.Preferences = @{}
            }
            $policies.policies.Preferences["extensions.ublock0.run_in_private_browsing"] = $true
            $policies | ConvertTo-Json -Depth 10 | Out-File -FilePath $policyPath -Encoding UTF8
            Write-Info "Updated Firefox policies.json to include uBlock Origin."
        }
        else {
            Write-Info "uBlock Origin is already configured in Firefox policies.json."
        }
    }
}

# Function to clone Git repository
function Clone-GitRepository {
    param(
        [Parameter(Mandatory=$true)]
        [string]$RepoURL,
        
        [Parameter(Mandatory=$true)]
        [string]$DestinationPath
    )

    if (-not (Test-Path $DestinationPath)) {
        Write-Info "Cloning repository from '$RepoURL' to '$DestinationPath'..."
        git clone $RepoURL $DestinationPath
        Write-Info "Repository cloned successfully."
    }
    else {
        Write-Info "Repository already exists at '$DestinationPath'. Skipping clone."
    }
}

# ----------------------------------------------
# 2. MAIN SCRIPT LOGIC
# ----------------------------------------------

# Define user credentials
$adminUserName = "AdminUser"
$adminPasswordPlain = "YourSecureAdminPassword123"  # Replace with a strong password
$streamerUserName = "Streamer"
$streamerPasswordPlain = "YourSecureStreamerPassword123"  # Replace with a strong password

# Define repository details
$repoURL = "https://github.com/GLam115/game-server-automation.git"
$repoDestination = "C:\ES\Media\Games\game-server-automation"

# Ensure the script is run as Administrator
if (-not (Test-Administrator)) {
    Write-ErrorMessage "Please run this script as Administrator!"
}

Write-Info "Starting provisioning process..."

# 2.1 Ensure Chocolatey is installed
Ensure-Chocolatey

# 2.2 Ensure required packages are installed or updated
# Updated package list: Added 'git'
$packages = @("googlechrome", "firefox", "dolphin", "qbittorrent", "playnite", "vlc", "steam", "steamcmd", "ds4windows", "parsec", "git")
foreach ($pkg in $packages) {
    Ensure-ChocoPackageInstalled -PackageName $pkg
}

# 2.3 Ensure local users
Ensure-LocalUser -UserName $adminUserName -PasswordPlainText $adminPasswordPlain -FullName "Admin User" -Description "Local Admin" -Group "Administrators"
Ensure-LocalUser -UserName $streamerUserName -PasswordPlainText $streamerPasswordPlain -FullName "Streamer User" -Description "Streaming Account" -Group "Users"

# 2.4 Create Desired Directory Structure
Write-Info "Creating directory structure..."

$directories = @(
    "C:\ES\Media\Games\PC",
    "C:\ES\Media\Games\Steam",
    "C:\ES\Media\Games\PS3",
    "C:\ES\Media\Games\Wii",
    "C:\ES\Media\Games\Saves"
)

foreach ($dir in $directories) {
    Ensure-Directory -DirectoryPath $dir
}

# 2.5 Clone Git Repository
Write-Info "Cloning Git repository..."
Clone-GitRepository -RepoURL $repoURL -DestinationPath $repoDestination

# 2.6 Configure Auto-Launch for Steam and Parsec
Write-Info "Configuring auto-launch for Steam and Parsec..."

$SteamUsername = $env:STEAM_USERNAME
$SteamPassword = $env:STEAM_PASSWORD

if (-not $SteamUsername -or -not $SteamPassword) {
    Write-Error "Environment variables STEAM_USERNAME and STEAM_PASSWORD must be set. Skipping steam login..."
} else {
    Write-Output "Logging into Steam..."
    Start-Process -NoNewWindow -FilePath $SteamCMDPath -ArgumentList "+login $SteamUsername $SteamPassword +quit" -Wait
}


# Check for Steam Guard prompt (manual intervention required if it appears)
if ($LastExitCode -ne 0) {
    Write-Error "Steam login failed. Please check your credentials or handle Steam Guard verification."
    #exit 1
}

Write-Output "Steam login successful."

# 2.7 Install and Configure uBlock Origin
Write-Info "Configuring uBlock Origin for Chrome and Firefox..."

Configure-ChromeUblockOrigin
Configure-FirefoxUblockOrigin

# 2.8 Pin Installed Applications to Taskbar
Write-Info "Pinning applications to the taskbar..."

$appsToPin = @(
    @{ Name = "steam" },
    @{ Name = "parsec" },
    @{ Name = "googlechrome" },
    @{ Name = "firefox" },
    @{ Name = "dolphin" },
    @{ Name = "playnite" },
    @{ Name = "vlc" },
    @{ Name = "qbittorrent" },
    @{ Name = "ds4windows" }
)

Pin-AppsToTaskbar -Apps $appsToPin

# ----------------------------------------------
# 3. REMOVED REGISTRY CONFIGURATION
# ----------------------------------------------
# The registry configuration section has been removed as it is no longer needed.
# Previously, it was used for enabling WSL-related features or other configurations
# that are not required in the current setup.

# ----------------------------------------------
# 4. FINALIZE SCRIPT
# ----------------------------------------------

Write-Info "Provisioning completed successfully!"

