# Windows Gaming Server Setup Script
<#
.SYNOPSIS
    Bootstrap and configure a Windows machine for a gaming/entertainment server.
.DESCRIPTION
    1. Checks for Administrator privileges
    2. Installs or updates Winget
    3. Creates local user accounts
    4. Creates directory structure for games and saves
    5. Installs required applications via Winget
    6. Configures remote access via Parsec
    7. Sets up system configurations for optimal gaming experience
.NOTES
    - Must be run as Administrator
    - Supports Windows 10 and 11
    - Focuses on game saves management rather than full system backups
#>

# ----------------------------
# Script Configuration
# ----------------------------
$ErrorActionPreference = "Stop"

# Allow override of base directory through environment variable
$baseDir = if ($env:ES_BASE_DIR) { $env:ES_BASE_DIR } else { "C:\ES" }
$gamesDir = Join-Path $baseDir "Games"
$logFile = Join-Path $baseDir "setup_log.txt"

# Create base directory if it doesn't exist
if (!(Test-Path $baseDir)) {
    New-Item -Path $baseDir -ItemType Directory -Force | Out-Null
}

# ----------------------------
# Logging Function
# ----------------------------
function Write-Log {
    param($Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp - $Message"
    Write-Host $logMessage
    if (!(Test-Path (Split-Path $logFile))) {
        New-Item -ItemType Directory -Path (Split-Path $logFile) -Force | Out-Null
    }
    $logMessage | Out-File -FilePath $logFile -Append
}

# ----------------------------
# OS Version Check
# ----------------------------
function Get-WindowsVersion {
    $osVersion = [System.Environment]::OSVersion.Version
    if ($osVersion.Major -eq 10) {
        return "Windows 10"
    } elseif ($osVersion.Build -ge 22000) {
        return "Windows 11"
    } else {
        throw "Unsupported Windows version"
    }
}

# ----------------------------
# Admin Check
# ----------------------------
function Test-AdminPrivileges {
    Write-Log "Checking for Administrator privileges..."
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if (-not $isAdmin) {
        throw "This script requires Administrator privileges"
    }
    Write-Log "Running with Administrator privileges"
}

# ----------------------------
# Winget Installation
# ----------------------------
function Install-WingetIfNeeded {
    Write-Log "Checking for Winget..."
    $wingetCheck = Get-Command "winget" -ErrorAction SilentlyContinue
    
    if (-not $wingetCheck) {
        Write-Log "Winget not found. Attempting to install..."
        try {
            Start-Process "ms-windows-store://pdp/?productid=9NBLGGH4NNS1" -Wait
            throw "Please install 'App Installer' from the Microsoft Store and rerun this script"
        }
        catch {
            throw "Failed to open Microsoft Store. Please install 'App Installer' manually"
        }
    }
    Write-Log "Winget is installed"
}

# ----------------------------
# User Account Management
# ----------------------------
function New-SecureUserAccount {
    param (
        [string]$UserName,
        [string]$Description,
        [bool]$IsAdmin = $false
    )
    
    $user = Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue
    if ($null -eq $user) {
        Write-Log "Creating user: $UserName"
        $securePassword = ConvertTo-SecureString "Ab12cd34" -AsPlainText -Force
        
        try {
            New-LocalUser -Name $UserName `
                         -Password $securePassword `
                         -PasswordNeverExpires $true `
                         -AccountNeverExpires $true `
                         -Description $Description `
                         -ErrorAction Stop
                         
            if ($IsAdmin) {
                Add-LocalGroupMember -Group "Administrators" -Member $UserName
                Write-Log "$UserName added to Administrators group"
            }
            Write-Log "User $UserName created successfully"
        }
        catch {
            Write-Log "Failed to create user $UserName : $($_.Exception.Message)"
            throw
        }
    }
    else {
        Write-Log "User $UserName already exists"
    }
}

# ----------------------------
# Directory Structure
# ----------------------------
function New-GameDirectories {
    Write-Log "Creating game directories..."
    $folders = @("Steam", "PC", "Wii", "PS3", "SaveFiles")
    
    foreach ($folder in $folders) {
        $path = Join-Path -Path $baseDir -ChildPath $folder
        if (!(Test-Path $path)) {
            try {
                New-Item -Path $path -ItemType "Directory" -Force | Out-Null
                Write-Log "Created directory: $path"
            }
            catch {
                Write-Log "Failed to create directory: $path"
                throw
            }
        }
    }
}

# ----------------------------
# Application Installation
# ----------------------------
function Install-RequiredApplications {
    Write-Log "Installing required applications..."
    
    $apps = @(
        @{ Name = "Google Chrome";    WingetId = "Google.Chrome" },
        @{ Name = "Mozilla Firefox";  WingetId = "Mozilla.Firefox" },
        @{ Name = "Dolphin Emulator"; WingetId = "DolphinEmulator.Dolphin" },
        @{ Name = "qBittorrent";      WingetId = "qBittorrent.qBittorrent" },
        @{ Name = "Playnite";         WingetId = "Playnite.Playnite" },
        @{ Name = "VLC";              WingetId = "VideoLAN.VLC" },
        @{ Name = "Steam";            WingetId = "Valve.Steam" },
        @{ Name = "SteamCMD";         WingetId = "McFarlus.SteamCMD" },
        @{ Name = "DS4Windows";       WingetId = "Ryochan7.DS4Windows" },
        @{ Name = "Parsec";           WingetId = "Parsec.Parsec" },
        @{ Name = "NordVPN";          WingetId = "NordSecurity.NordVPN" },
        @{ Name = "Git";              WingetId = "Git.Git" }
    )
    
    foreach ($app in $apps) {
        Write-Log "Installing $($app.Name)..."
        try {
            winget install --id $($app.WingetId) --exact --accept-package-agreements --accept-source-agreements --silent
            Write-Log "$($app.Name) installed successfully"
        }
        catch {
            Write-Log "Failed to install $($app.Name): $($_.Exception.Message)"
            # Continue with other installations even if one fails
        }
    }
}

# ----------------------------
# Remote Access Configuration
# ----------------------------
function Set-ParsecConfig {
    Write-Log "Configuring Parsec..."
    
    # Configure Parsec autostart
    # Determine Parsec paths dynamically
    $parsecDir = "$env:APPDATA\Parsec"
    $parsecPath = Join-Path $parsecDir "parsecd.exe"
    $startupFolder = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
    $parsecDataDir = "$env:APPDATA\Parsec"
    
    if (Test-Path $parsecPath) {
        # Create autostart shortcut
        $shortcutPath = "$startupFolder\Parsec.lnk"
        $WScriptShell = New-Object -ComObject WScript.Shell
        $shortcut = $WScriptShell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $parsecPath
        $shortcut.Save()
        Write-Log "Parsec configured for autostart"

        # Configure basic Parsec settings
        $parsecConfig = @"
[host]
encoder_bitrate=50
encoder_min_bitrate=10
encoder_h264_quality=2
encoder_yuv_quality=2
encoder_vsync=1
network_server_port=8000

[client]
app_run=1
app_background=1
app_autostart=1
wayland=0
"@
        $parsecConfig | Out-File -FilePath "$parsecDataDir\config.txt" -Encoding UTF8

        # Configure auto-login if credentials are provided
        if ($env:PARSEC_EMAIL -and $env:PARSEC_PASSWORD) {
            Write-Log "Configuring Parsec auto-login..."
            $credentialsPath = "$parsecDataDir\user.bin"
            @{
                user = $env:PARSEC_EMAIL
                password = $env:PARSEC_PASSWORD
                auto_login = 1
            } | ConvertTo-Json | Out-File -FilePath $credentialsPath -Encoding UTF8
            Write-Log "Parsec auto-login configured"
        } else {
            Write-Log "Parsec credentials not provided, skipping auto-login setup"
        }
    }
}

# ----------------------------
# Steam Configuration
# ----------------------------
function Set-SteamConfig {
    Write-Log "Configuring Steam..."
    
    # Determine Steam path based on architecture and existing installation
    $steamPath = $null
    $possibleSteamPaths = @(
        "${env:ProgramFiles(x86)}\Steam",
        "$env:ProgramFiles\Steam",
        "$env:ProgramW6432\Steam"
    )
    
    foreach ($path in $possibleSteamPaths) {
        if (Test-Path $path) {
            $steamPath = $path
            break
        }
    }
    
    if (!$steamPath) {
        # If Steam isn't found, default to the most appropriate path based on architecture
        if ([Environment]::Is64BitOperatingSystem) {
            $steamPath = "${env:ProgramFiles(x86)}\Steam"
        } else {
            $steamPath = "$env:ProgramFiles\Steam"
        }
    
    if (Test-Path $steamPath) {
        # Check for Steam credentials in environment
        if ($env:STEAM_USERNAME -and $env:STEAM_PASSWORD) {
            Write-Log "Configuring Steam auto-login..."
            
            # Create Steam auto-login configuration
            $steamConfigPath = "$steamPath\config\loginusers.vdf"
            $steamConfig = @"
"users"
{
    "0"
    {
        "AccountName"    "$($env:STEAM_USERNAME)"
        "RememberPassword"    "1"
        "WantsOfflineMode"    "0"
        "SkipOfflineModeWarning"    "0"
        "AllowAutoLogin"    "1"
        "MostRecent"    "1"
    }
}
"@
            # Create config directory if it doesn't exist
            New-Item -ItemType Directory -Force -Path "$steamPath\config" | Out-Null
            $steamConfig | Out-File -FilePath $steamConfigPath -Encoding UTF8
            Write-Log "Steam auto-login configured"
        } else {
            Write-Log "Steam credentials not provided, skipping auto-login setup"
        }
    } else {
        Write-Log "Steam installation not found"
    }
}

# ----------------------------
# System Configuration
# ----------------------------
function Set-SystemConfig {
    Write-Log "Configuring system settings..."
    
    # Power settings
    powercfg /change standby-timeout-ac 0
    powercfg /change monitor-timeout-ac 0
    Write-Log "Power settings configured"
    
    # Network settings
    Enable-NetFirewallRule -DisplayGroup "File and Printer Sharing"
    Write-Log "Network settings configured"
    
    # Windows Update settings
    if (!(Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update")) {
        New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update" -Force
    }
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update" -Name "AUOptions" -Value 4
    Write-Log "Windows Update configured"
}

# ----------------------------
# Validation
# ----------------------------
function Test-Installation {
    Write-Log "Validating installation..."
    
    $tests = @{
        "Winget" = { Get-Command winget -ErrorAction SilentlyContinue }
        "Parsec" = { Test-Path "$env:APPDATA\Parsec\parsecd.exe" }
        "Steam"  = { Test-Path "C:\Program Files (x86)\Steam\steam.exe" }
        "Game Directories" = { Test-Path $baseDir }
    }
    
    foreach ($test in $tests.GetEnumerator()) {
        if (& $test.Value) {
            Write-Log "$($test.Name) validation successful"
        } else {
            Write-Log "$($test.Name) validation failed"
        }
    }
}

# ----------------------------
# Main Execution
# ----------------------------
try {
    Write-Log "Starting setup script..."
    
    Test-AdminPrivileges
    $windowsVersion = Get-WindowsVersion
    Write-Log "Detected OS: $windowsVersion"
    
    Install-WingetIfNeeded
    New-GameDirectories
    
    # Create user accounts
    New-SecureUserAccount -UserName "Admin" -Description "Administrator Account" -IsAdmin $true
    New-SecureUserAccount -UserName "mediauser" -Description "Media User Account" -IsAdmin $false
    New-SecureUserAccount -UserName "streamer" -Description "Streaming Account" -IsAdmin $false
    New-SecureUserAccount -UserName "guest1" -Description "Guest Account" -IsAdmin $false
    
    Install-RequiredApplications
    Set-ParsecConfig
    Set-SystemConfig
    Set-SteamConfig
    Test-Installation
    
    Write-Log "Setup completed successfully!"
}
catch {
    Write-Log "Error occurred: $($_.Exception.Message)"
    Write-Host "Setup failed. Check $logFile for details." -ForegroundColor Red
    exit 1
}
