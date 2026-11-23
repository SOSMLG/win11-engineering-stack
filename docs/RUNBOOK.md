# Runbook

## First run

```powershell
cd path\to\win11-engineering-stack
.\Install.ps1 -Profile daily -DryRun
.\Install.ps1 -Profile daily
```

The script elevates itself once. If a reboot is required, it stops and prints the
resume command. Run it after the reboot:

```powershell
.\Install.ps1 -Profile daily -Resume
```

## Common invocations

```powershell
# OS features only, with the ISO payload.
.\Install.ps1 -Profile daily -Only os -SxsPath D:\sources\sxs

# Apps and editor extensions.
.\Install.ps1 -Profile daily -Only apps

# Engineering folders, MATLAB env, installer launch.
.\Install.ps1 -Profile daily -Only engineering -TiaInstaller D:\TIA\Start.exe -MatlabInstaller D:\MATLAB\setup.exe

# Theme and configs only.
.\Install.ps1 -Profile daily -Only theme,configs

# Saved daily state and the next command.
.\Install.ps1 -Profile daily -Status

# Read-only reports. both are write-free.
.\Validate.ps1
.\Validate.ps1 -Profile iot
```

## What is manual

1. **TIA Portal**: finish the installer, license it, and set the PG/PC interface
   to the PLC NIC. The script only enables prerequisites and starts the
   installer.
2. **MATLAB**: finish the installer and sign in. Rerun `-Only engineering` to set
   `MATLABROOT` and `PATH` after the install.
3. **ONLYOFFICE defaults**: Settings -> Apps -> Default apps -> ONLYOFFICE for
   `.docx`, `.xlsx`, `.pptx`.
4. **LibreWolf**: open each profile shortcut and sign in separately. Set it as
   default in Settings -> Apps -> Default apps -> Web browser. Windows protects
   that choice, so the script only prints the step.
5. **qBittorrent**: WebUI ships off. If you turn it on in the app, set a local
   password there; no password is stored in the repo.
6. **KeePassXC**: create the database in `Documents\Vaults`.
7. **OmniRoute**: open `http://127.0.0.1:20128/dashboard`, connect providers, and
   confirm `OMNIROUTE_API_KEY` is a user environment variable. The installer
   also sets `OMNIROUTE_SERVER_HOST=127.0.0.1` and `REQUIRE_API_KEY=true`.
8. **GitHub**: `gh auth login` if needed, then
   `gh ssh-key add $HOME\.ssh\id_ed25519.pub`.
9. **Reboot or sign out** once after the theme module so Windows applies the
   light mode and accent.

## Troubleshooting

### Feature enablement fails

Check the image first:

```powershell
Get-WindowsOptionalFeature -Online -FeatureName NetFx3
Test-Path C:\Windows\WinSxS
```

If WinSxS is missing, the image cannot be serviced. Rebuild it. If the payload is
missing but WinSxS exists, mount the matching ISO and pass
`-SxsPath <ISO>\sources\sxs`.

### winget is missing

The apps module skips winget packages and says so. Install App Installer from
the Microsoft Store or rebuild the image with it. Do not add a silent package
manager bootstrap; it hides the failure.

### OmniRoute does not start

```powershell
omniroute serve --no-open --log
Invoke-WebRequest http://127.0.0.1:20128/v1/models
```

Logs are under `%USERPROFILE%\.omniroute\logs`. If the dashboard opens but
OpenCode gets 401, the API key in `OMNIROUTE_API_KEY` does not match the
dashboard key.

If `netstat -ano | findstr :20128` shows `0.0.0.0`, set
`OMNIROUTE_SERVER_HOST=127.0.0.1` as a user variable, then run
`omniroute stop` and `.\scripts\Install.ps1 -Only omniroute`. The validate
module fails when the listener is not loopback-only.

If OmniRoute warns that `STORAGE_ENCRYPTION_KEY` is missing but
`~/.omniroute/storage.sqlite` exists, restore the key from
`~/.omniroute/.env`. Do not delete the database to silence the warning.

### OpenCode ignores the provider

```powershell
Get-Content $HOME\.config\opencode\opencode.json -Raw | ConvertFrom-Json
```

The config must use `providers` (plural), `package`, and `settings.baseURL`.
Restart OpenCode after changing it. If it still fails, start OpenCode with its
log level raised and check for a schema error.

### TIA Portal cannot see the PLC

- Confirm the PG/PC interface uses the physical adapter, not "S7-ONLINE" on
  Wi-Fi.
- Confirm TCP 102 is allowed on the active profile. The script only opens
  Domain and Private; set the PLC network to Private, never Public.
- Disable Wi-Fi while commissioning if the route is ambiguous.
- PROFINET DCP is Layer 2; a firewall rule will not fix a blocked switch port or
  VLAN.

### MATLAB is not on PATH

Rerun `.\scripts\Install.ps1 -Only engineering` after installing MATLAB. It sets
`MATLABROOT` and appends `<root>\bin` to the machine PATH. Open a new terminal.

### LibreWolf profile creation fails

Close every LibreWolf window, then rerun `.\Install.ps1 -Profile daily -Only
developer`. On IoT, rerun `.\Install.ps1 -Profile iot -ConfigsOnly`. The profile name
must not already exist in `%APPDATA%\LibreWolf\profiles.ini`.

## Rollback

Config backups:

```text
%LOCALAPPDATA%\win11-stack\backups\<timestamp>\
```

Logs:

```text
%LOCALAPPDATA%\win11-stack\logs\
```

The installer never removes Windows features. To undo the OS module:

```powershell
Disable-WindowsOptionalFeature -Online -FeatureName MSMQ-Server -NoRestart
Disable-WindowsOptionalFeature -Online -FeatureName IIS-WebServerRole -NoRestart
```

Remove the firewall rules by display name:

```powershell
Get-NetFirewallRule -DisplayName 'TIA Portal S7*' | Remove-NetFirewallRule
```

Uninstall apps through Settings -> Apps. MercuryGram is portable: delete
`%LOCALAPPDATA%\Programs\Mercurygram` and the two shortcuts.
