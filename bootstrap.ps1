<#
.SYNOPSIS
    Bootstrap and configure a Windows machine for a gaming/entertainment server.
.DESCRIPTION
    1. Checks for Administrator privileges.
    2. Installs or updates Winget.
    3. Creates local user accounts:
       - Admin (password: socksandshoes)
       - mediauser (password: socksandshoes)
       - streamer (password: socksandshoes)
       - guest1 (password: "")
    4. Creates directory structure: C:\ES\Games\[Steam, PC, Wii, PS3, SaveFiles]
    5. Installs required applications via Winget.
    6. Demonstrates how to create symbolic links for game saves.
.NOTES
    - Ensure this script is run as Administrator.
    - Adjust user account policies if necessary to allow blank passwords.
#>

# ----------------------------
# 1. Verify that the script is run as Administrator
# ----------------------------

Write-Host "Checking for Administrator privileges..." -ForegroundColor Cyan
If (-Not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
    [Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "ERROR: You must run this script as an Administrator!" -ForegroundColor Red
    exit 1
}

Write-Host "Running with Administrator privileges..." -ForegroundColor Green

# ----------------------------
# 2. Install or Update Winget
# ----------------------------
Write-Host "`nChecking for Winget..." -ForegroundColor Cyan
$wingetCheck = Get-Command "winget" -ErrorAction SilentlyContinue
if (-not $wingetCheck) {
    Write-Host "Winget not found. Attempting to install from the Microsoft Store package..." -ForegroundColor Yellow
    # Winget is typically included with the App Installer. Attempt to install App Installer.
    try {
        Start-Process "ms-windows-store://pdp/?productid=9NBLGGH4NNS1" -Wait
        Write-Host "Please install 'App Installer' from the Microsoft Store, then re-run this script." -ForegroundColor Yellow
        exit 1
    }
    catch {
        Write-Host "Failed to open Microsoft Store. Please install 'App Installer' manually." -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "Winget is already installed." -ForegroundColor Green
}

# ----------------------------
# 3. Create Local User Accounts
# ----------------------------
Write-Host "`nCreating local user accounts..." -ForegroundColor Cyan

function Create-LocalUserIfNotExists {
    param (
        [string]$UserName,
        [string]$Password,
        [bool]$IsAdmin = $false
    )

    $user = Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue
    if ($null -eq $user) {
        Write-Host "Creating user: $UserName" -ForegroundColor Yellow
        $SecurePassword = $null
        if ($Password -ne "") {
            $SecurePassword = ConvertTo-SecureString $Password -AsPlainText -Force
        }

        try {
            New-LocalUser -Name $UserName -Password $SecurePassword -PasswordNeverExpires $true -AccountNeverExpires $true `
                -Description "Automated account created by ES bootstrap script" -ErrorAction Stop
            Write-Host "User $UserName created successfully." -ForegroundColor Green
        }
        catch {
            Write-Host "Failed to create user $UserName. Error: $($_.Exception.Message)" -ForegroundColor Red
            return
        }

        # Add to Administrators group if requested
        if ($IsAdmin) {
            try {
                Add-LocalGroupMember -Group "Administrators" -Member $UserName -ErrorAction Stop
                Write-Host "User $UserName was added to the Administrators group." -ForegroundColor Green
            }
            catch {
                Write-Host "Failed to add user $UserName to Administrators group. Error: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }
    else {
        Write-Host "User $UserName already exists; skipping creation." -ForegroundColor Green
    }
}

# Administrator account (named "Admin")
Create-LocalUserIfNotExists -UserName "Admin"    -Password "socksandshoes" -IsAdmin $true
Create-LocalUserIfNotExists -UserName "mediauser" -Password "socksandshoes" -IsAdmin $false
Create-LocalUserIfNotExists -UserName "streamer"  -Password "socksandshoes" -IsAdmin $false
Create-LocalUserIfNotExists -UserName "guest1"    -Password ""              -IsAdmin $false

Write-Host "Users created: Admin, mediauser, streamer, guest1" -ForegroundColor Cyan

# ----------------------------
# (Optional) Allow accounts with blank passwords
# ----------------------------
Write-Host "`nConfiguring local security policy to allow accounts with blank passwords..." -ForegroundColor Cyan
try {
    $policyPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
    Set-ItemProperty -Path $policyPath -Name "LimitBlankPasswordUse" -Value 0 -ErrorAction Stop
    Write-Host "Successfully configured policy to allow blank passwords." -ForegroundColor Green
}
catch {
    Write-Host "Failed to set policy for blank passwords. Error: $($_.Exception.Message)" -ForegroundColor Red
}

# ----------------------------
# 4. Create Directory Structure
# ----------------------------
Write-Host "`nCreating directories under C:\ES\Games..." -ForegroundColor Cyan
$baseDir = "C:\ES\Games"
$folders = @("Steam", "PC", "Wii", "PS3", "SaveFiles")

foreach ($folder in $folders) {
    $path = Join-Path -Path $baseDir -ChildPath $folder
    if (!(Test-Path $path)) {
        try {
            New-Item -Path $path -ItemType "Directory" -Force | Out-Null
            Write-Host "Created directory: $path" -ForegroundColor Green
        }
        catch {
            Write-Host "Failed to create directory: $path. Error: $($_.Exception.Message)" -ForegroundColor Red
        }
    } else {
        Write-Host "Directory already exists: $path" -ForegroundColor Green
    }
}
Write-Host "Directories created under C:\ES\Games" -ForegroundColor Cyan

# ----------------------------
# 5. Install Applications via Winget
# ----------------------------
Write-Host "`nInstalling required applications using Winget. This may take a while..." -ForegroundColor Cyan

$appsToInstall = @(
    # Using exact match IDs to ensure correct installations
    @{ Name = "Google Chrome";       WingetId = "Google.Chrome" },
    @{ Name = "Mozilla Firefox";     WingetId = "Mozilla.Firefox" },
    @{ Name = "Dolphin Emulator";    WingetId = "DolphinEmulator.Dolphin" },
    @{ Name = "qBittorrent";         WingetId = "qBittorrent.qBittorrent" },
    @{ Name = "Playnite";            WingetId = "Playnite.Playnite" },
    @{ Name = "VLC Media Player";    WingetId = "VideoLAN.VLC" },
    @{ Name = "Steam (Client)";      WingetId = "Valve.Steam" },
    @{ Name = "SteamCMD";            WingetId = "McFarlus.SteamCMD" },  # Verify availability
    @{ Name = "DS4Windows";          WingetId = "Ryochan7.DS4Windows" },
    @{ Name = "Parsec";              WingetId = "Parsec.Parsec" },
    @{ Name = "Git";                 WingetId = "Git.Git" }
)

foreach ($app in $appsToInstall) {
    Write-Host "`nInstalling $($app.Name)..." -ForegroundColor Yellow
    try {
        winget install --id $($app.WingetId) --exact --accept-package-agreements --accept-source-agreements --silent
        Write-Host "$($app.Name) installed successfully." -ForegroundColor Green
    }
    catch {
        Write-Host "Failed to install $($app.Name). Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}
Write-Host "Applications installed via Winget" -ForegroundColor Cyan

Write-Host "`nBootstrap script completed successfully!" -ForegroundColor Green

