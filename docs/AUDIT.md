# Folder and machine audit

Date: 2026-11-21

## Source folder

`C:\Users\Admin\Downloads\Ultimate-Win11-Setup-main\Ultimate-Win11-Setup-main`

This is a themed ricing/dotfiles collection, not a Windows setup framework.
Only a few pieces fit an engineering workstation.

| Item | Decision | Reason |
|---|---|---|
| `Terminal/settings.json` | Keep the scheme | Graphite Amber + JetBrains Mono is readable and low contrast. |
| `VSCode/Settings/settings.json` | Cherry-pick | Keep cursor, theme, and layout ideas. Drop pets, animations, Copilot, and the invalid trailing commas. |
| `PowerShell/Microsoft.PowerShell_profile.ps1` | Keep UTF-8 block | Drop `Clear-Host` and unconditional `fastfetch`. |
| `Flow Launcher/Theme` | Optional | Only if Flow Launcher is used. PowerToys Run is lighter. |
| `Discord/System24 Theme` | Optional | Can be imported into Vesktop/Vencord. |
| `YASB`, `GlazeWM`, `Komorebi` | Drop | Two tiling WMs plus a custom bar add startup complexity and fight TIA/MATLAB dialogs. |
| `Windhawk`, `File Explorer` blur | Drop | Explorer/taskbar injection is a stability risk. The source README warns about crashes. |
| `Cava`, `OBS`, `Cursor`, `Screenshots`, `Fastfetch` | Drop | Cosmetic or unrelated. |
| `LICENSE` | Keep if reusing configs | MIT attribution. |

## Machine snapshot

| Check | Result |
|---|---|
| OS | AspectOS x NanoWin, Windows 11 Enterprise LTSC, build 26100 |
| Defender | Missing (`Get-MpComputerStatus` and `WinDefend` absent) |
| winget | Missing (no App Installer alias) |
| IIS/MSMQ | Services absent; feature state needs elevation |
| .NET 4.8 | Present, release 533320 |
| Long paths | Enabled |
| VSCodium | 1.143.17232, Python/Jupyter/GitLens extensions present |
| ONLYOFFICE | Installed |
| TIA Portal / MATLAB | Not installed |
| Node.js | 26.13.1 |
| Python | 3.15 via `py`; `python` is not on PATH |
| OmniRoute | CLI 3.8.54 installed, server not running |
| OpenCode | V1 `provider` shape, 399 models, titstack `AGENTS.md` loaded globally |
| Git/gh | gh authenticated over HTTPS, SSH key exists, Git email unset |
| Network | Wi-Fi (RTL8852AE) and Realtek Ethernet; no PLC adapter connected |

The image findings are the reason the installer checks guardrails first. The
script can configure apps on this image, but it cannot honestly provide
antivirus or reliably enable .NET 3.5/IIS/MSMQ without WinSxS.

## Config decisions

- The source VSCodium settings use extensions that are unavailable or unwanted
  on Open VSX. The deployed set uses Python, debugpy, Jupyter, Ruff,
  BasedPyright and autoDocstring. The dark base uses local color customizations.
- GitLens is not deployed. If it is already installed, the apps module removes
  it; the built-in Git view covers the common cases.
- The source PowerShell profile is reduced to UTF-8 and Python UTF-8 settings.
  No `fastfetch`, no `Clear-Host`, no prompt framework.
- No custom cursors, wallpapers with busy art, or window animations. The theme
  is intentionally quiet: light shell, dark editor and terminal.
