# Entertainment Server Automation

Automate the setup of a Windows-based entertainment server for gaming and media management.

A starter documentation for setting up a Windows-based entertainment server to manage games, media, and save files in a structured, automated way. This project leverages Ansible, Chocolatey (or Winget), and other tools to simplify installation, configuration, and ongoing management.

## Features
- User account creation (Admin, Streamer)
- Installation of essential software via Chocolatey
- Structured directory setup for games and save files
- Symbolic links for centralized save file management
- Google Drive installation for save files backup
- Remote control of torrenting

#cd /Users/glam3k/Library/Mobile\ Documents/iCloud~md~obsidian/Documents/'# Directory Structure

## Setup

### Step 1: Provision machine

Use the unattend.iso file to set up a new machine.
Generated from:

```
https://schneegans.de/windows/unattend-generator/?LanguageMode=Unattended&UILanguage=en-US&Locale=en-US&Keyboard=00000409&GeoLocation=244&ProcessorArchitecture=x86&ProcessorArchitecture=amd64&ProcessorArchitecture=arm64&BypassNetworkCheck=true&ComputerNameMode=Random&CompactOsMode=Default&TimeZoneMode=Implicit&PartitionMode=Unattended&PartitionLayout=GPT&EspSize=300&RecoveryMode=Partition&RecoverySize=1000&WindowsEditionMode=Generic&WindowsEdition=pro&UserAccountMode=Unattended&AccountName0=Admin&AccountPassword0=yn4%40kg9%26&AccountGroup0=Administrators&AccountName1=mediauser&AccountPassword1=socksandshoes&AccountGroup1=Users&AccountName2=streamer&AccountPassword2=yn4%40kg9%26&AccountGroup2=Users&AccountName3=guest1&AccountPassword3=&AccountGroup3=Users&AccountName4=&AutoLogonMode=Own&ObscurePasswords=true&PasswordExpirationMode=Unlimited&LockoutMode=Default&HideFiles=Hidden&ShowFileExtensions=true&TaskbarSearch=Box&TaskbarIconsMode=Default&StartTilesMode=Default&StartPinsMode=Default&WifiMode=Interactive&ExpressSettings=DisableAll&KeysMode=Skip&ColorMode=Default&WallpaperMode=Default&WdacMode=Skip
 ```

### Step 2: Run the setup script

Admin password:
yn4@kg9&

`script`

## Media

All directories created for the files related to this project will start at C://ES. We use ES, since other names like "Games" or "Media" are created by default by Windows or other applications.

1. **Save Files Syncing**  
   - The `SaveFiles` directory can be selectively synced to cloud storage (Google Drive, OneDrive, etc.).  
   - Configure cloud clients 

2. **Directory Layout**  
   - By default, the script creates a `C:ES\Games` directory with subfolders for:
     - `Steam`
     - `PC` (e.g., Dolphin)
     - `Wii`
     - `PS3`
     - `SaveFiles`

3. **Symbolic Links**  
   - The system can create symbolic links redirecting individual game save locations to `C:\Games\SaveFiles`.  
   - This ensures all saves are centrally located and backed up.

4. **Game Organization**  
   - **Playnite** consolidates different game sources (Steam, emulator-based, or manually added games).  
   - **Steam** installation is handled automatically; emulated or pirated games can be dropped into the respective folders.

## TODO
1. Explore media servers
2. Wake on LAN
3. Storage/adding storage
4. Backup/snapshots of media
5. Remote torrenting GUI
6. Integrate steam
7. Backup system of save files

## notes
1. nordvpn install seems to fail for winget

