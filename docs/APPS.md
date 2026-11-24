# desktop apps

one inventory for the apps this repo installs or configures. config paths are
per-user. the installer never writes an app password or an API key into these
files.

| app | profile | source | repo config | theme |
| --- | --- | --- | --- | --- |
| 7-Zip | daily, iot | `7zip.7zip` | none needed | native light |
| qBittorrent | iot | `qBittorrent.qBittorrent` | `qBittorrent/qbittorrent.ini` | native light |
| Windows Terminal | daily, iot | `Microsoft.WindowsTerminal` | `WindowsTerminal/settings.json` | Graphite Amber |
| VSCodium | daily, iot | `VSCodium.VSCodium` | `config/vscodium/settings.json`, `VSCodium/graphite-amber-theme/` | Graphite Amber |
| LibreWolf | daily, iot | `LibreWolf.LibreWolf` | `LibreWolf/librewolf.overrides.cfg` | native light |
| Vesktop | daily, iot | `Vencord.Vesktop` | `config/vesktop/settings.json`, `Vesktop/quickcss.css` | Graphite Amber |
| Joplin | daily, iot, optional | `Joplin.Joplin` | `config/joplin/settings.json` | native light |
| Spotube | iot, optional | `KRTirtho.Spotube` | app-managed | native light |
| Mem Reduct | iot, optional | `Henry++.MemReduct` | `MemReduct/memreduct.ini` | native light |

## 7-Zip

Installed when `7z.exe` is absent. The IoT self-check also accepts
`C:\Program Files\7-Zip\7z.exe`, because 7-Zip does not always add `7z` to
`PATH`. No repo config; keep the shipped shell integration as-is.

## qBittorrent

`qBittorrent/qbittorrent.ini` is copied fresh-only to
`%APPDATA%\qBittorrent\qbittorrent.ini`. The shipped state is:

- WebUI off; loopback address only if you turn it on locally.
- No web username or password hash in the repo.
- UPnP off; DHT, PeX, and Local Peer Discovery on.
- Downloads under `C:/Users/Public/Downloads`; queue 5 downloads and 5 uploads.

If you enable WebUI by hand, set the password in the app. That value stays in
your user config and is not part of this repository.

## Windows Terminal

`WindowsTerminal/settings.json` is copied fresh-only by the IoT profile. The
daily theme module also maintains the Graphite Amber scheme and applies it to
terminal defaults. It keeps Windows PowerShell 5.1 and Command Prompt, removes
the stale PowerShell 7 profile, starts in `%USERPROFILE%`, and uses no acrylic
or transparency.

## VSCodium

Both profiles use the bundled `xfcemlg.graphite-amber-theme-0.6.0` extension.
The daily theme module installs it fresh-only; the IoT profile copies the
extension folder. `workbench.colorTheme` is set to `Graphite Amber` in both
settings templates. Telemetry is off and updates are manual.

## LibreWolf

LibreWolf is the browser in the IoT app list. The installer:

- copies `librewolf.overrides.cfg` fresh-only to
  `%USERPROFILE%\.librewolf\librewolf.overrides.cfg`;
- creates `personal`, `uni`, and `social` profiles under
  `%APPDATA%\LibreWolf\Profiles`;
- adds Start Menu shortcuts that open each profile with `-P <name> -no-remote`.

The overrides file uses `defaultPref`, so UI changes win. It only sets startup
behavior and a close-tabs warning. Windows protects the default browser
choice, so set LibreWolf as default by hand in
`Settings > Apps > Default apps > Web browser`.

## Vesktop

Vesktop and Vencord settings are merged into
`%APPDATA%\vesktop\settings.json` and
`%APPDATA%\vesktop\settings\settings.json`. `Vesktop/quickcss.css` supplies the
Graphite Amber Quick CSS. Close Vesktop before changing these files; it
rewrites settings on exit.

## Joplin

Joplin is the FOSS notes replacement for Obsidian. The installer seeds
`config/joplin/settings.json` to `%USERPROFILE%\.config\joplin-desktop\settings.json`
on a fresh profile. It sets the light theme, code view, spellcheck, and
`sync.target: 0` so the first run stays local. Existing settings are kept on
re-run. Daily `-Force` replaces them after a backup; IoT `-Force` overwrites
without one. Sync is a one-time Joplin setting if you want it.

## Spotube

Spotube is the FOSS Spotify client. It is installed by winget, or from the
GitHub release when winget is missing. Its settings live in Flutter
`shared_preferences.json` and are not stable across releases, so the installer
does not ship a fake config. The first-run wizard is a one-time step.

## Outlook

The default debloat pass removes `Microsoft.OutlookForWindows` and the
provisioned package, then turns off the consumer-app reinstall switches. Classic
Outlook from a paid Office install is not touched.

## Mem Reduct

IoT app included by default; `-Minimal` skips it. Winget ID is
`Henry++.MemReduct`. `memreduct.ini` is copied fresh-only to
`%APPDATA%\Henry++\Mem Reduct\memreduct.ini`. The repo file is comment-only so
Mem Reduct can write its own settings on first run. No autostart, no interval
cleanup, and no registry edits. It needs admin rights when you run it because
it uses Native APIs.

## theme boundary

Graphite Amber belongs in terminals, editors, and Vesktop. Engineering and
daily-use desktop apps keep their native light UI so TIA Portal, MATLAB,
ONLYOFFICE, dialogs, and file pickers stay readable.
