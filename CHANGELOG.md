# changelog

format follows keep a changelog. versions are git tags like `v0.1.0`.

## [Unreleased]
### added
- repository health files and read-only CI validation.

### changed
- renamed the repo to `win11-engineering-stack`. the old URL still redirects.
- merged the modular daily installer, the daily config set and their docs into this repo. `Install.ps1` and `Validate.ps1` are the front doors for both profiles.
- OpenCode now uses one V2 config with `providers` and `permissions`. the old root config is gone.
- the deployed opencode config no longer loads context7 and playwright into every message. an existing `~\.config\opencode\opencode.json` is kept (fresh-only), see `docs/OPENCODE.md` to switch.
- Defender is left as shipped. no script writes its preferences or disables real-time protection.
- missing winget is a skip with manual IDs in the README, not a failed run.
- OmniRoute logon tasks use a `.cmd` wrapper so `.cmd` CLI shims work.
- README and docs describe installs and configs only; tweak and OOSU notes are gone.

### removed
- removed every Windows optimization on request. gone: the IoT tweak/debloat phases, `-TweaksOnly`, the tweak matrix, O&O config, Lenovo charge cap, DNS/power/taskbar/privacy tuning, temp cleanup, the daily privacy, power, PLC and Defender-exclusion code, and the unused root `lib/` helpers. these are manual now.
- dropped the study pack: Zotero, SumatraPDF, MiKTeX, Typst and their configs. Windows Terminal moved into the base app list.
- dropped Komorebi and whkd, including keybinds, WM config, autostart shortcuts and smoke checks. the desktop is stock Windows now.
- dropped the ISO builder, autounattend templates and `templates/`. offline installs still work through `-OfflineDir`.
- deleted the `tests/` suite on request. `-DryRun` is the remaining preflight check.

### fixed
- `Git/.gitconfig` is deployed fresh-only. it has a blank identity, so overwriting on re-run would have wiped the user's name and email.
- `Git/.gitconfig` was missing from the repo. the installer logged a skip and the README promised it.
- `.gitignore` was missing. AGENTS.md says it excludes `*.iso`, `ISO/build/`, `ISO/Offline/`.
- removed a stray 2-byte file `ISO/s`.

### added
- OpenCode setup rebuilt around measured token cost (see `docs/OPENCODE.md`). per message on 1.19.4: old config ~14,400, new default ~8,500, `lean` ~3,500.
- `config/opencode.json`: context7 and playwright gated per agent (`web`, `lookup`), pinned versions, agents `lean` `web` `lookup` `docs` `video` `review`, commands `/commit` `/handoff` `/rmslop` `/usage` `/review`, permissions, watcher ignores.
- `config/AGENTS.global.md` and `config/opencode-skills/` (ffmpeg, latex, powershell 5.1, playwright), deployed fresh-only by the installer.
- `tools/token-audit/oc_token_audit.py`: measures what OpenCode sends per message, per tool and per MCP server, offline.
- `.gitattributes`, `.editorconfig`, `opencode.json` (project permissions, review agent, slash commands).
- docs: `docs/OPENCODE.md`, `CONTRIBUTING.md`, `SECURITY.md`, `THIRD-PARTY-NOTICES.md`.
