# Research notes

## Image: Nano11 versus stock LTSC

Nano11-class images remove Defender, Windows Update, the component store, and
most services. That breaks three requirements at once:

- no resident antivirus;
- `.NET 3.5`, IIS, and MSMQ cannot be enabled if the payload is gone;
- winget/App Installer cannot be installed reliably.

`10-OS` therefore reads the feature state first and reports `Unknown` instead of
claiming success. The recommended base is stock Windows 11 LTSC media with
Defender, WinSxS, Windows Update, and App Installer intact.

## TIA Portal V18

Prerequisites reported by Siemens and the TIA installer:

- .NET Framework 3.5 and 4.8;
- IIS with ASP.NET 4.x, WCF HTTP activation, and MSMQ;
- Visual C++ runtimes;
- WebView2 for help and some installers;
- a reboot after feature enablement.

Windows 11 build 26100 is outside the V18 launch matrix (21H2/22H2). V18 Update
5+ is the safer bet on 24H2; V19/V20 are the clean option. The script enables the
features and firewall rule, but cannot validate Siemens' support matrix.

## PROFINET and S7

- S7 engineering uses TCP 102. The script adds inbound and outbound rules for
  Domain and Private profiles only.
- PROFINET DCP and RT are Layer 2 (EtherType `0x8892`). Windows Firewall does not
  filter them, so no firewall rule can fix a bad NIC or switch configuration.
- The PG/PC interface must point at the physical PLC adapter. That is a manual
  TIA Portal step.

## Antivirus

There is no trustworthy lightweight FOSS resident antivirus for Windows.
Bitdefender Free is closed source; Avast/AVG bundle unwanted components. The
setup keeps Defender as installed and leaves real-time protection, reporting,
scans, and exclusions untouched.

## VSCodium

- VSCodium uses Open VSX. Pylance is not available.
- `ms-python.python` is available; set `python.languageServer` to `None` and use
  BasedPyright for type analysis.
- Ruff handles formatting and import sorting.
- Telemetry is off and updates are manual.

## OmniRoute and OpenCode

- OmniRoute listens on `127.0.0.1:20128`; the OpenAI-compatible base URL is
  `/v1`.
- Provider fallback happens inside OmniRoute combos (`auto/coding`,
  `auto/fast`), not in OpenCode.
- `omniroute setup-opencode` still writes the old V1 `provider` shape. The
  deployed config uses V2 `providers`, `package`, and `settings.baseURL`.
- OpenCode has no `.opencodeignore`. `watcher.ignore` filters events but is not a
  hard read boundary. Use a real `.git` plus `.gitignore`, `watcher.ignore`, and
  permission deny rules.

## Local accounts

- KeePassXC for the vault. The script creates the folder, never a database.
- LibreWolf profiles `personal`, `uni`, and `social`, each with its own cookie
  jar and sign-in. LibreWolf is already hardened; the script does not add
  prefs that could break sites. Ungoogled Chromium is a valid alternative, but
  LibreWolf's profile isolation and update path are simpler on Windows.
- GitHub CLI uses SSH for Git; its other defaults stay as shipped.

## Desktop apps

- Telegram Desktop is installed from winget. MercuryGram Desktop is the manual
  portable alternative: v7.4.4.1, SHA256
  `BCE4A20B0389095CCD5DF95C24FC0F9CA23D4EAF758F259986AC579F548F1774`.
  `tdata` stays next to the executable.
- Vesktop uses `%APPDATA%\vesktop\settings.json`; Vencord uses
  `%APPDATA%\vesktop\settings\settings.json`. Close Vesktop before editing,
  because it rewrites settings on exit.
- ONLYOFFICE default associations cannot be set silently. Windows 11 protects
  `UserChoice`; the script points at `ms-settings:defaultapps`.

## FOSS replacements

| Instead of | Use | Note |
|---|---|---|
| Microsoft Office | ONLYOFFICE | Installed; set defaults manually. |
| Chrome/Edge for personal use | LibreWolf | Separate profiles, no Google sync. |
| Discord desktop | Vesktop | Vencord, lower overhead, no telemetry plugins. |
| Telegram Desktop | MercuryGram (manual) | Portable, pinned release. |
| WinRAR | 7-Zip | No nag screen. |
| Browser password store | KeePassXC | Local vault, no cloud. |
| Flow Launcher | PowerToys Run | One less background app. |

## Theme

TIA Portal, MATLAB, and ONLYOFFICE are light-themed and do not tolerate dark
injection well. The shell stays light; editors, terminals, and Vesktop use
Catppuccin Mocha. This keeps dialogs readable and avoids white flashes against a
dark desktop.
