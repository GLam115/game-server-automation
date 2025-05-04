# Windows Gaming Server Setup Script
<#
.SYNOPSIS
    Bootstrap and configure a Windows machine as a gaming/entertainment server.
.DESCRIPTION
    1. Checks for Administrator privileges
    2. Installs or updates Winget
    3. Creates directory structure for games and media
    4. Installs required applications via Winget
.NOTES
    - Must be run as Administrator
    - Supports Windows 10 and 11
#>

$ErrorActionPreference = "Stop"

$baseDir = if ($env:ES_BASE_DIR) { $env:ES_BASE_DIR } else { "C:\ES" }
$logFile = Join-Path $baseDir "setup_log.txt"

$script:SuccessCount = 0
$script:FailureCount = 0
$script:Failures = @()

if (!(Test-Path $baseDir)) {
    New-Item -Path $baseDir -ItemType Directory -Force | Out-Null
}

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("Info", "Warning", "Error")][string]$Level = "Info"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp [$Level] - $Message"
    Write-Host $logMessage -ForegroundColor $(switch ($Level) { "Error" { "Red" } "Warning" { "Yellow" } default { "White" } })
    if (!(Test-Path (Split-Path $logFile))) {
        New-Item -ItemType Directory -Path (Split-Path $logFile) -Force | Out-Null
    }
    $logMessage | Out-File -FilePath $logFile -Append
}

function Record-Result {
    param([bool]$Success, [string]$Operation)
    if ($Success) {
        $script:SuccessCount++
    } else {
        $script:FailureCount++
        $script:Failures += $Operation
    }
}

function Get-WindowsVersion {
    Write-Log "Checking Windows version..."
    $osVersion = [System.Environment]::OSVersion.Version
    if ($osVersion.Major -eq 10) {
        Write-Log "Detected Windows 10"
        return "Windows 10"
    } elseif ($osVersion.Build -ge 22000) {
        Write-Log "Detected Windows 11"
        return "Windows 11"
    } else {
        Write-Log "Unsupported Windows version" -Level "Error"
        throw "Unsupported Windows version"
    }
}

function Test-AdminPrivileges {
    Write-Log "Checking for Administrator privileges..."
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if (-not $isAdmin) {
        Write-Log "This script requires Administrator privileges" -Level "Error"
        throw "This script requires Administrator privileges"
    }
    Write-Log "Running with Administrator privileges"
}

function Install-WingetIfNeeded {
    Write-Log "Checking for Winget..."
    if (-not (Get-Command "winget" -ErrorAction SilentlyContinue)) {
        Write-Log "Winget not found. Attempting to install..." -Level "Warning"
        try {
            $wingetUrl = "https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
            $tempPath = "$env:TEMP\winget.msixbundle"
            Invoke-WebRequest -Uri $wingetUrl -OutFile $tempPath
            Add-AppxPackage -Path $tempPath
            Remove-Item $tempPath
            Write-Log "Winget installed successfully"
        }
        catch {
            Write-Log "Failed to install Winget: $($_.Exception.Message)" -Level "Error"
            throw
        }
    } else {
        Write-Log "Winget is installed"
        Write-Log "Checking for Winget updates..."
        winget upgrade --id Microsoft.AppInstaller --silent --accept-source-agreements
    }
}

function New-ESDirectories {
    Write-Log "Creating ES directories..."
    
    $directories = @{
        "Games" = @("Steam", "PC", "Wii", "PS3", "SaveFiles")
        "Media" = @("Movies", "Shows")
    }

    foreach ($mainDir in $directories.Keys) {
        $mainPath = Join-Path -Path $baseDir -ChildPath $mainDir
        if (!(Test-Path $mainPath)) {
            try {
                New-Item -Path $mainPath -ItemType Directory -Force | Out-Null
                Write-Log "Created main directory: $mainPath"

                foreach ($subDir in $directories[$mainDir]) {
                    $subPath = Join-Path -Path $mainPath -ChildPath $subDir
                    New-Item -Path $subPath -ItemType Directory -Force | Out-Null
                    Write-Log "Created subdirectory: $subPath"
                }
                Record-Result -Success $true -Operation "Create directory $mainPath"
            }
            catch {
                Write-Log "Failed to create directory structure under $mainPath : $($_.Exception.Message)" -Level "Error"
                Record-Result -Success $false -Operation "Create directory $mainPath"
                throw
            }
        } else {
            Write-Log "Directory $mainPath already exists"
        }
    }
    Write-Log "Directory structure created successfully"
}

function Install-RequiredApplications {
    Write-Log "Installing required applications..."
    
    $apps = @(
        @{ Name = "Google Chrome";    WingetId = "Google.Chrome" },
        @{ Name = "Mozilla Firefox";  WingetId = "Mozilla.Firefox" },
        @{ Name = "Dolphin Emulator"; WingetId = "DolphinEmulator.Dolphin" },
        @{ Name = "Playnite";         WingetId = "Playnite.Playnite" },
        @{ Name = "VLC";              WingetId = "VideoLAN.VLC" },
        @{ Name = "Steam";            WingetId = "Valve.Steam" },
        @{ Name = "Sunshine";         WingetId = "LizardByte.Sunshine" },
        @{ Name = "TeamViewer";       WingetId = "TeamViewer.TeamViewer" },
        @{ Name = "RustDesk";         WingetId = "RustDesk.RustDesk" }
    )

    $total = $apps.Count
    $current = 0

    foreach ($app in $apps) {
        $current++
        Write-Progress -Activity "Installing applications" -Status "Installing $($app.Name)" -PercentComplete (($current / $total) * 100)
        Write-Log "Checking $($app.Name)..."
        $appInstalled = winget list --id $($app.WingetId) --exact --accept-source-agreements --disable-interactivity | Select-String $app.WingetId
        if (-not $appInstalled) {
            Write-Log "Installing $($app.Name)..."
            try {
                winget install --id $($app.WingetId) --exact --accept-package-agreements --accept-source-agreements --silent
                Write-Log "$($app.Name) installed successfully"
                Record-Result -Success $true -Operation "Install $($app.Name)"
            }
            catch {
                Write-Log "Failed to install $($app.Name): $($_.Exception.Message)" -Level "Error"
                Record-Result -Success $false -Operation "Install $($app.Name)"
            }
        } else {
            Write-Log "$($app.Name) is already installed"
            Record-Result -Success $true -Operation "Install $($app.Name)"
        }
    }
    Write-Progress -Activity "Installing applications" -Completed
}

# Main Execution
try {
    Test-AdminPrivileges
    Get-WindowsVersion | Out-Null
    Install-WingetIfNeeded
    New-ESDirectories
    Install-RequiredApplications
    Write-Log "Setup completed successfully."
}
catch {
    Write-Log "Script failed: $($_.Exception.Message)" -Level "Error"
    $script:FailureCount++
    $script:Failures += "Main execution"
}
finally {
    Write-Log "Script completed. Successes: $SuccessCount, Failures: $FailureCount"
    if ($FailureCount -gt 0) {
        Write-Log "Failed operations: $($Failures -join ', ')" -Level "Warning"
    }
}
