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
        [string]$Group = "Users"  # Default group
    )

    $user = Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue
    if ($null -eq $user) {
        Write-Info "User '$UserName' does not exist. Creating..."
        $securePass = ConvertTo-SecureString $PasswordPlainText -AsPlainText -Force
        New-LocalUser -Name $UserName -Password $securePass -FullName $FullName -Description $Description
        
        # Add user to the specified group
        Write-Info "Adding '$UserName' to '$Group' group."
        Add-LocalGroupMember -Group $Group -Member $UserName
    }
    else {
        Write-Info "User '$UserName' already exists. Ensuring group membership..."
        $currentGroups = Get-LocalGroupMember -Group $Group -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $UserName }
        if (-not $currentGroups) {
            Add-LocalGroupMember -Group $Group -Member $UserName
            Write-Info "Added '$UserName' to '$Group' group."
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

# Function to set Steam to launch at startup
function Set-SteamAutoLaunch {
    $steamPath = "C:\Program Files (x86)\Steam\Steam.exe"
    $startupFolder = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
    $shortcutPath = Join-Path -Path $startupFolder -ChildPath "Steam.lnk"

    if (-not (Test-Path $shortcutPath)) {
        Write-Info "Creating Steam shortcut in Startup folder for auto-launch..."
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $steamPath
        $shortcut.WorkingDirectory = "C:\Program Files (x86)\Steam"
        $shortcut.Save()
    }
    else {
        Write-Info "Steam shortcut already exists in Startup folder. Skipping."
    }
}

# Function to set Parsec to launch at startup
function Set-ParsecAutoLaunch {
    $parsecPath = "C:\Program Files\Parsec\Parsec.exe"
    $startupFolder = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
    $shortcutPath = Join-Path -Path $startupFolder -ChildPath "Parsec.lnk"

    if (-not (Test-Path $shortcutPath)) {
        Write-Info "Creating Parsec shortcut in Startup folder for auto-launch..."
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $parsecPath
        $shortcut.WorkingDirectory = "C:\Program Files\Parsec"
        $shortcut.Save()
    }
    else {
        Write-Info "Parsec shortcut already exists in Startup folder. Skipping."
    }
}

# ----------------------------------------------
# 2. MAIN SCRIPT LOGIC
# ----------------------------------------------

# Ensure the script is run as Administrator
if (-not (Test-Administrator)) {
    Write-ErrorMessage "Please run this script as Administrator!"
}

Write-Info "Starting provisioning process..."

# 2.1 Ensure Chocolatey is installed
Ensure-Chocolatey

# 2.2 Ensure required packages are installed or updated
$packages = @("git", "python", "googlechrome", "qbittorrent", "steam", "ds4windows")
foreach ($pkg in $packages) {
    Ensure-ChocoPackageInstalled -PackageName $pkg
}

# 2.3 Ensure local users
# NOTE: Replace the password placeholders with secure methods to handle passwords
# Example: Using encrypted credentials or prompting for input
$adminUsername = "AdminUser"
$adminPassword = "P@ssw0rd123"   # Replace with secure method
$streamerUsername = "Streamer"
$streamerPassword = "P@ssw0rd123" # Replace with secure method

Ensure-LocalUser -UserName $adminUsername -PasswordPlainText $adminPassword -FullName "Admin User" -Description "Local Admin" -Group "Administrators"
Ensure-LocalUser -UserName $streamerUsername -PasswordPlainText $streamerPassword -FullName "Streamer User" -Description "Streaming Account" -Group "Users"

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

# 2.5 Configure Auto-Launch for Steam and Parsec
Write-Info "Configuring auto-launch for Steam and Parsec..."

Set-SteamAutoLaunch
Set-ParsecAutoLaunch

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
