<div align="center">
  <img src="assets/banner.svg" alt="Windows engineering stack" width="100%" />
</div>

<div align="center">

# win11-engineering-stack

one Windows setup repo, two profiles: `daily` for engineering work and `iot` for
slim Win10/Win11 IoT Enterprise LTSC boxes. native PowerShell 5.1, one config
tree, dry-run before every write.

![powershell](https://img.shields.io/badge/PowerShell-5.1-5391FE?style=for-the-badge)
![windows](https://img.shields.io/badge/Windows-10%2F11-0078D6?style=for-the-badge)
![profile](https://img.shields.io/badge/profiles-daily%20%2F%20iot-2f81f7?style=for-the-badge)
![license](https://img.shields.io/badge/license-MIT-3fb950?style=for-the-badge)

</div>

> this changes system settings. run `-DryRun` first, then read
> [docs/RUNBOOK.md](docs/RUNBOOK.md) for the run order and
> [SECURITY.md](SECURITY.md) for the Ventoy answer file. try it in a VM before a
> real machine.

## quick start

```powershell
# one front door, two profiles
.\Install.ps1 -Profile daily -DryRun
.\Install.ps1 -Profile daily

.\Install.ps1 -Profile iot -DryRun
.\Install.ps1 -Profile iot
```

double-click `Setup.cmd` for the old one-click IoT path. it still passes extra
flags through.

read-only checks:

```powershell
.\Validate.ps1 -Profile iot
.\Validate.ps1 -Profile daily
```

or call the profile directly:

```powershell
.\install-Win-Iot.ps1 -Verify
.\scripts\Validate.ps1
```

## profiles

| profile | entry point | what it does |
| --- | --- | --- |
| `daily` | `scripts/Install.ps1` | OS features, winget apps, TIA/MATLAB paths, VSCodium, Git/gh, developer accounts, OmniRoute, theme, configs |
| `iot` | `install-Win-Iot.ps1` | unattended slim LTSC build, offline-first engines, stock desktop, per-app configs |

both profiles share `config/`. the daily profile uses the modular files under
`config/opencode`, `config/vscodium`, `config/vesktop`, and `config/vencord`.
the IoT profile keeps its own `config/defaults.json` and `config/hashes.json`.
imported reference copies from the old daily repo live under `config/daily/`.

## daily modules

```
preflight  os  packages  apps  engineering  developer  omniroute  theme  configs  validate
```

run one part with `-Only`:

```powershell
.\scripts\Install.ps1 -Only os,apps -SxsPath D:\sources\sxs
.\scripts\Install.ps1 -Only engineering -TiaInstaller D:\TIA\Start.exe -MatlabInstaller D:\MATLAB\setup.exe
.\scripts\Install.ps1 -Resume
```

## IoT flags

the full list is in `install-Win-Iot.ps1 -?`. the ones used most:

| flag | what it does |
| --- | --- |
| `-DryRun` | print every write, download, and install step, then stop |
| `-Verify` | check repo configs and installed state, exit 1 if anything is missing |
| `-Unattended` | no prompts |
| `-ConfigsOnly` | re-copy user configs, nothing else |
| `-OfflineDir <path>` | install from staged files; winget is not required |
| `-NoWingetBootstrap` | skip App Installer bootstrap; staged and direct sources still apply |
| `-DriverDir <path>` | install drivers from a folder |
| `-Only`, `-SkipApps` | filter the app list |
| `-Fixes` | repair DNS, winsock, and the update stack |

## behavior

- **dry-run is safe.** no files, registry keys, services, or installs change.
- **idempotent.** state lives in `%LOCALAPPDATA%\win11-stack` for daily runs and
  next to the log for IoT runs. `-Force` reruns skipped work.
- **logs.** daily logs land in `%LOCALAPPDATA%\win11-stack\logs`. IoT logs land
  in `C:\Windows\Logs\Win-Iot-Setup`, with a fallback to `%TEMP%` when not
  elevated.
- **winget missing.** the daily profile prints a skip and leaves apps alone.
  install App Installer, then install by hand with these IDs:
  `VSCodium.VSCodium`, `Git.Git`, `GitHub.cli`, `OpenJS.NodeJS.LTS`,
  `Python.Python.3.12`, `7zip.7zip`, `Microsoft.VCRedist.2015+.x64`,
  `Microsoft.VCRedist.2015+.x86`, `Microsoft.EdgeWebView2Runtime`,
  `Microsoft.PowerToys`, `KeePassXCTeam.KeePassXC`, `LibreWolf.LibreWolf`,
  `ONLYOFFICE.DesktopEditors`, `Vencord.Vesktop`, `Microsoft.WindowsTerminal`,
  `DEVCOM.JetBrainsMonoNerdFont`.
- **IoT package sources.** staged files first, then winget, then GitHub releases or
  direct vendor URLs. no third-party package manager is bootstrapped.
- **Defender.** stays as shipped. no script writes its preferences or disables
  real-time protection.

## OmniRoute and OpenCode

OmniRoute listens on `127.0.0.1:20128`. create a tool key in its dashboard and
set `OMNIROUTE_API_KEY` as a user environment variable. the installer never
writes the key to a file. OpenCode uses the V2 `providers` shape from
`config/opencode/opencode.json`. deny rules live in `permissions`, and the
watcher ignore list lives in `watcher.ignore`.

the logon task uses a small `.cmd` wrapper under `%LOCALAPPDATA%\win11-stack\bin`
because `omniroute` can resolve to a `.cmd` shim on Windows.

## repo layout

| path | what |
| --- | --- |
| `Install.ps1`, `Validate.ps1` | one front door for both profiles |
| `scripts/` | daily modules, shared helpers, read-only validator |
| `config/` | shared config tree and IoT defaults |
| `docs/` | OpenCode notes, audit, research, runbook |
| `ventoy/` | answer files for Ventoy media |
| app folders | per-app config plus a short note |
| `tools/` | local token audit helper |

## docs

- [OPENCODE.md](docs/OPENCODE.md)
- [RUNBOOK.md](docs/RUNBOOK.md)
- [AUDIT.md](docs/AUDIT.md)
- [RESEARCH.md](docs/RESEARCH.md)
- [CONTRIBUTING.md](CONTRIBUTING.md)
- [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md)

## license

MIT. see [LICENSE](LICENSE).

## more from SOSMLG

- [DebianSway](https://github.com/SOSMLG/DebianSway) - sway/wayland desktop for Debian and Devuan
- [DevuanDwm](https://github.com/SOSMLG/DevuanDwm) - dwm-based minimal desktop for Devuan
- [XfceMlg](https://github.com/SOSMLG/XfceMlg) - XFCE rice for Debian and Devuan
- [profile and all repos](https://github.com/SOSMLG) - notes, configs, and the rest of the setups

bugs and ideas go in [issues](https://github.com/SOSMLG/win11-engineering-stack/issues).

## Repository standard

This repo follows the SOSMLG standard: [contributing](CONTRIBUTING.md), [security](SECURITY.md), [changelog](CHANGELOG.md). Local workflow: [English guide](https://github.com/SOSMLG/.github/blob/main/docs/GIT_GUIDE.md) / [Arabic guide](https://github.com/SOSMLG/.github/blob/main/docs/GIT_GUIDE.ar.md).
