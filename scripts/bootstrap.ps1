# Run as Administrator

# --------------------------------------------
# Variables - Configure these as needed
# --------------------------------------------

# Repository Configuration
$RepoURL = "https://github.com/GLam115/game-server-automation.git" # Replace with your repository URL
$RepoName = "game-server-automation" # Repository folder name after cloning

# --------------------------------------------
# Script Logging Setup
# --------------------------------------------

$LogFile = "C:\Temp\InstallAnsibleAndRun.log"
if (-not (Test-Path "C:\Temp")) {
    New-Item -Path "C:\Temp" -ItemType Directory -Force
}
Start-Transcript -Path $LogFile -Append

Write-Output "========== [Start Bootstrap Script] =========="

try {
    # Set Execution Policy
    Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
    Write-Output "Set ExecutionPolicy to Bypass for the current session."

    # Install WSL and Ubuntu Distribution
    Write-Output "Installing WSL and Ubuntu distribution..."
    wsl --install -d Ubuntu
    Write-Output "WSL and Ubuntu installation initiated."

    # Enable WinRM on the Windows Host
    Enable-PSRemoting -Force
    Set-Item -Path WSMan:\localhost\Service\Auth\Basic -Value $true
    Set-Item -Path WSMan:\localhost\Service\AllowUnencrypted -Value $true
    netsh advfirewall firewall add rule name="WinRM HTTP" dir=in action=allow protocol=TCP localport=5985


    # Function to Check if a Restart is Required
    function Test-PendingReboot {
        # Check registry keys that indicate a pending reboot
        $pendingReboot = Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" `
                         -or Test-Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\PendingFileRenameOperations"
        return $pendingReboot
    }

    # Check for Pending Reboot and Schedule Continuation Script
    if (Test-PendingReboot) {
        Write-Output "A system restart is required to complete WSL installation."

        # Define the path for the continuation script
        $scriptPath = "C:\Temp\ContinueSetup.ps1"

        if (-not (Test-Path $scriptPath)) {
            Write-Output "Creating continuation script at $scriptPath..."

            # Define the content of the continuation script
            $continueScriptContent = @"
# ContinueSetup.ps1
# Run as Administrator

# Enable script logging
\$LogFile = "C:\Temp\ContinueSetup.log"
if (-not (Test-Path "C:\Temp")) {
    New-Item -Path "C:\Temp" -ItemType Directory -Force
}
Start-Transcript -Path \$LogFile -Append

Write-Output "========== [Continue Setup Script Started] =========="

try {
    # 1. Set Execution Policy
    Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
    Write-Output "Set ExecutionPolicy to Bypass for the current session."

    # 2. Set WSL default version to 2
    Write-Output "Setting WSL default version to 2..."
    wsl --set-default-version 2
    Write-Output "WSL default version set to 2."

    # 3. Update and Upgrade Ubuntu Packages
    Write-Output "Updating and upgrading Ubuntu packages..."
    wsl -d Ubuntu -- sudo apt-get update -y && sudo apt-get upgrade -y
    Write-Output "Ubuntu packages updated and upgraded."

    # 4. Install Necessary Packages: python3-pip and git
    Write-Output "Installing Python3-pip and Git..."
    wsl -d Ubuntu -- sudo apt-get install -y python3-pip git
    Write-Output "Python3-pip and Git installed."

    # 5. Install Ansible via pip
    Write-Output "Installing Ansible via pip..."
    wsl -d Ubuntu -- pip3 install --upgrade ansible
    Write-Output "Ansible installed."

    # 6. Clone the Ansible Repository
    Write-Output "Determining WSL username..."
    \$wslUser = wsl whoami
    \$RepoPath = "/home/\$wslUser/$RepoName"

    Write-Output "Cloning Ansible repository into WSL at \$RepoPath..."
    wsl -d Ubuntu -- bash -c "git clone \$RepoURL \$RepoPath || (cd \$RepoPath && git pull)"
    Write-Output "Ansible repository cloned or updated."

    # 7. Run the Ansible Playbook
    Write-Output "Executing Ansible playbook..."
    wsl -d Ubuntu -- bash -c "cd \$RepoPath && ansible-playbook -i inventory/hosts.ini playbooks/setup_windows.yml"
    Write-Output "Ansible playbook executed successfully."

    # 8. Delete the Scheduled Task to Prevent Re-running
    Write-Output "Deleting the scheduled continuation task..."
    schtasks /Delete /TN "ContinueSetup" /F
    Write-Output "Scheduled task 'ContinueSetup' deleted."

    Write-Output "========== [Continue Setup Script Complete] =========="
}
catch {
    Write-Error "An error occurred during continuation setup: \$_"
}
finally {
    Stop-Transcript
}
"@

            # Write the continuation script to the designated path
            $continueScriptContent | Out-File -FilePath $scriptPath -Encoding UTF8
            Write-Output "Continuation script created at $scriptPath."
        }
        else {
            Write-Output "Continuation script already exists at $scriptPath."
        }

        # --------------------------------------------
        # 5. Schedule the Continuation Script to Run at Next Startup
        # --------------------------------------------
        Write-Output "Scheduling the continuation script to run at next startup..."
        schtasks /Create /SC ONSTART /TN "ContinueSetup" /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:\Temp\ContinueSetup.ps1'" /RU "SYSTEM" /RL HIGHEST /F
        Write-Output "Continuation script scheduled as 'ContinueSetup' task."

        # Initiate System Reboot
        Write-Output "Rebooting the system to complete WSL installation..."
        Restart-Computer -Force
    }
    else {
        Write-Output "No restart required. Proceeding with setup..."

        # Set WSL Default Version to 2
        Write-Output "Setting WSL default version to 2..."
        wsl --set-default-version 2
        Write-Output "WSL default version set to 2."

        # Update and Upgrade Ubuntu Packages
        Write-Output "Updating and upgrading Ubuntu packages..."
        wsl -d Ubuntu -- sudo apt-get update -y && sudo apt-get upgrade -y
        Write-Output "Ubuntu packages updated and upgraded."

        # Install Necessary Packages: python3-pip and git
        Write-Output "Installing Python3-pip and Git..."
        wsl -d Ubuntu -- sudo apt-get install -y python3-pip git
        Write-Output "Python3-pip and Git installed."

        # Install Ansible via pip
        Write-Output "Installing Ansible via pip..."
        wsl -d Ubuntu -- pip3 install --upgrade ansible
        wsl -d Ubuntu -- pip3 install --upgrade pywinrm
        Write-Output "Ansible installed."

        # Clone the Ansible Repository
        Write-Output "Determining WSL username..."
        $wslUser = wsl whoami
        $RepoPath = "/home/$wslUser/$RepoName"

        Write-Output "Cloning Ansible repository into WSL at $RepoPath..."
        wsl -d Ubuntu -- bash -c "git clone $RepoURL $RepoPath || (cd $RepoPath && git pull)"
        Write-Output "Ansible repository cloned or updated."

        # Run the Ansible Playbook
        Write-Output "Executing Ansible playbook..."
        wsl -d Ubuntu -- bash -c "cd $RepoPath && ansible-playbook -i inventory/hosts.ini playbooks/setup_windows.yml"
        Write-Output "Ansible playbook executed successfully."

        Write-Output "========== [Bootstrap Script Complete] =========="
    }
}
catch {
    Write-Error "An error occurred during bootstrap: $_"
}
finally {
    Stop-Transcript
}

