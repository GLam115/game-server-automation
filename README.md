# Entertainment Server Automation

Automate the setup of a Windows-based entertainment server for gaming and media management.

## Features

- User account creation (Admin, Streamer)
- Installation of essential software via Chocolatey
- Structured directory setup for games and save files
- Symbolic links for centralized save file management
- Google Drive installation for save files backup
- Remote control of torrenting

## Directory Structure

## Run the playbook

ansible-playbook -i inventory/localhost.ini playbooks/setup_windows.yml --ask-vault-pass
