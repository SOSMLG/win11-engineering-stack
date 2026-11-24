# changelog

format follows keep a changelog. versions are git tags like `v0.1.0`.

## [Unreleased]
### added
- one default debloat pass for both profiles, driven by `config/debloat.json`. it applies UI, privacy, and provider values, removes the consumer app set including Outlook for Windows, blocks consumer-app reinstall, and disables only CEIP/Appraiser/reporting tasks. `-NoDebloat` is a recovery switch, not a tier.
- Joplin as the FOSS notes app and Spotube as the FOSS Spotify client. Joplin gets a local-only light seed config; Spotube keeps its first-run wizard.
- repository health files and read-only CI validation.
- `docs/APPS.md` with install IDs, config paths, theme scope, and manual steps for the desktop apps.
- configured LibreWolf and Mem Reduct folders. LibreWolf gets safe `defaultPref` overrides and three profiles; Mem Reduct gets a comment-only portable config.

### changed
- the IoT browser is now `LibreWolf.LibreWolf` with configured profiles and overrides. Default browser is a printed Settings step, not a forced launch.
- qBittorrent now ships with WebUI off, UPnP off, no web password in the repo, and loopback only for local opt-in.
- Windows Terminal keeps Windows PowerShell 5.1 and Command Prompt, starts in the user profile, and drops the stale PowerShell 7 entry.
- daily and IoT VSCodium settings now activate the bundled Graphite Amber theme instead of a default theme with duplicate color overrides.
- rewrote the README around quick start, profiles, verification, and repo layout. added `QUICKSTART.md` and local Graphite Amber preview cards. refreshed repo description and topics.
- switched banners, badges, VSCodium, and Windows Terminal to Graphite Amber. the old theme family is gone.
- renamed the repo to `win11-engineering-stack`. the old URL still redirects.
- merged the modular daily installer, the daily config set and their docs into this repo. `Install.ps1` and `Validate.ps1` are the front doors for both profiles.
- OpenCode now uses one V2 config with `providers` and `permissions`. the old deployed V1 config is gone; the root `opencode.json` is repo-only.
- the deployed opencode config no longer loads context7 and playwright into every message. an existing `~\.config\opencode\opencode.json` is kept (fresh-only), see `docs/OPENCODE.md` to switch.
- Defender, Windows Update, Store, Terminal, WebView2, and .NET are left alone by the debloat pass. it never touches those services, tasks, or packages.
- missing winget is a skip with manual IDs in the README, not a failed run. on IoT, apps with a GitHub or direct source still install; AppX and scheduled-task cmdlets missing are skips, not failures.
- `Setup.cmd` exits clean on success and pauses only on failure.
- README, QUICKSTART, CLI, APPS, SECURITY, THIRD-PARTY-NOTICES, and the IoT preview describe the post-install profiles, the FOSS app choices, and the single debloat pass.
- OmniRoute logon tasks use a `.cmd` wrapper so `.cmd` CLI shims work.
- README and docs describe installs and configs only; tweak and OOSU notes are gone.

### removed
- removed every Windows optimization on request. gone: the old tiered tweak/debloat phases, `-TweaksOnly`, the tweak matrix, O&O config, Lenovo charge cap, DNS/power/taskbar/privacy tuning, temp cleanup, the daily privacy, power, PLC and Defender-exclusion code, and the unused root `lib/` helpers. these are manual now. the new single debloat pass is a separate, fixed set.
- removed the third-party package-manager bootstrap and fallback engine from the IoT installer. package sources are now staged files, winget, GitHub releases, and direct vendor URLs.
- dropped the study pack: Zotero, SumatraPDF, MiKTeX, Typst and their configs. Windows Terminal moved into the base app list.
- dropped Komorebi and whkd, including keybinds, WM config, autostart shortcuts and smoke checks. no tiling WM remains; the shell is stock Windows plus one fixed debloat pass.
- dropped the ISO builder, autounattend templates and `templates/`. offline installs still work through `-OfflineDir`.
- deleted the `tests/` suite on request. `-DryRun` is the remaining preflight check.

### fixed
- IoT runs now exit 1 when an app install actually failed, so `Setup.cmd` pauses instead of claiming success. Skip-only misses on stripped images still exit 0.
- staged Spotube now uses the NSIS `/S` switch, and its GitHub fallback uses the canonical `team-spotube/spotube` repo.
- Joplin seed config now uses valid setting keys and keeps a light theme with `themeAutoDetect` off.
- `Install.ps1 -Verify` is an alias for the matching validator, `Install.ps1 -Status` reports saved daily state, and `Validate.ps1` defaults to `daily`.
- the UAC relaunch waits for the elevated child and returns its exit code. daily modules can mark failure, and the run summary prints ok, skip, warn, and fail counts with the next command.
- the IoT 7-Zip smoke test accepts `C:\Program Files\7-Zip\7z.exe` when `7z` is not on `PATH`.
- IoT `-Verify` now reads the VSCodium theme property directly. the old call used a helper that the standalone script never loaded, so existing settings were misreported as invalid JSON.
- dry-run output now says that logs and the IoT report are still written. theme and config messages no longer claim a write happened in dry-run.
- daily module discovery now uses `-File`, and preflight no longer creates the log root that the front door already creates.
- daily validation now reuses the OmniRoute loopback helper instead of repeating the listener check.
- the Git config template is deployed fresh-only when present. it has a blank identity, so overwriting on re-run would wipe the user's name and email.
- the missing `Git/` template is now a logged skip, not a README promise.
- `.gitignore` was missing. AGENTS.md says it excludes `*.iso`, `ISO/build/`, `ISO/Offline/`.
- removed a stray 2-byte file `ISO/s`.

### added
- OpenCode setup rebuilt around measured token cost (see `docs/OPENCODE.md`). per message on 1.19.4: old config ~14,400, new default ~8,500, `lean` ~3,500.
- `config/opencode/opencode.json`: context7 and playwright gated per agent (`web`, `lookup`), pinned versions, agents `lean` `web` `lookup` `docs` `video` `review`, commands `/commit` `/handoff` `/rmslop` `/usage` `/review`, permissions, watcher ignores.
- `config/AGENTS.global.md`, `config/opencode/AGENTS.md`, and `config/opencode-skills/` (ffmpeg-recipes, powershell-5-1), deployed by the installer.
- `tools/token-audit/oc_token_audit.py`: measures what OpenCode sends per message, per tool and per MCP server, offline.
- `.gitattributes`, `.editorconfig`, `opencode.json` (project permissions, review agent, slash commands).
- docs: `docs/OPENCODE.md`, `CONTRIBUTING.md`, `SECURITY.md`, `THIRD-PARTY-NOTICES.md`.
