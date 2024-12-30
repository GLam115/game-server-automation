$repoUrl  = "https://github.com/your-username/entertainment-server-automation.git"
$repoPath = "C:\AnsibleRepo"
Write-Host "Running Ansible playbook..."
Set-Location $repoPath
ansible-playbook -i "localhost," -c local playbooks/setup_windows.yml

Write-Host "========== [Ansible Automation Complete] =========="
