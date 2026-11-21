# AGENTS.md - notes for any coding agent working in this folder

## What this is
Slim Win10/Win11 IoT LTSC setup: PowerShell base, Helium, VSCodium, stock Windows desktop.
Unattended installer: `install-Win-Iot.ps1` (`-TweaksOnly` for tweaks-only runs).
Ventoy answer files live in `ventoy/script/`. Taste port from the sibling linux
project `..\XfceMlg` (VSCodium theme, Vesktop quickcss, shell pack, battery manners).

## Rules learned the hard way
- Native exes (DISM, powercfg, installers) don't throw in PowerShell.
  Always check `$LASTEXITCODE`. try/catch alone lies.
- `winget download` filenames embed the installer tech
  (`_<scope>_<arch>_<tech>_<lang>.<ext>`). Read the tech for silent flags,
  don't guess: `_burn_` = /install /quiet, `_exe_` legacy redists = /q,
  `_wix_` = .msi, `_inno_` = /VERYSILENT, `_nullsoft_` = /S.
- Unknown keys in vlcrc/qbittorrent.ini/OBS basic.ini are ignored, so
  best-effort keys are safe there.
- Vencord ignores unknown plugin names in settings.json. Still, only add
  plugin names verified against vencord.dev/plugins.
- Voice: comments and logs read like one tired human. Short, lowercase
  asides, no em-dashes, no buzzwords, no triplets. Never "improve" wording
  in a way that touches logic. Check syntax after every edit:
  `powershell -NoProfile -Command "$null=[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path .\install-Win-Iot.ps1),[ref]$null,[ref]$null)"`.
  A real run always starts with `-DryRun`.
- New switches stay additive: `-DryRun`, `-Verify`, `-Only`, `-SkipApps`
  all default off and guard every write site. When adding a write, add a
  dry-run log line for it. `Complete-Phase` never marks done in dry-run;
  the log + report json still get written (that is the dry-run deliverable).
- ThinkPad charge cap: lenovo-only, gated on the PWRMGRV key or the
  IBMPMDRV service, so non-lenovo machines just log a skip. The exe comes
  from lenovo's cdn, is sha256-pinned in `config/hashes.json` (refresh the
  pin when lenovo ships a new build) and signature-checked, never bundled.
  `-SkipBatteryCap` opts out. "already capped" only counts on a positive ON
  from the exe; anything unparsed gets the cap set. The ChargeStart/Stop reg
  fallback mirrors a known driver bug that makes a fresh threshold read back
  OFF, don't delete it.
- Vesktop quickcss upgrades only when the file is untouched (exact old
  placeholder, whitespace/BOM-insensitive) or empty. Anyone who added rules
  under the old marker keeps their file. `Test-QuickcssStale` owns the rule,
  in the installer.
- Shell profile hooks (starship/zoxide/eza/fzf) are all `Get-Command`
  guarded, and fastfetch only fires on an interactive console with output
  not redirected. Drop that guard and installs drown in fastfetch.
- VSCodium folder extensions need the `publisher.name-version` folder name
  matching package.json, or codium acts like the theme is not installed.
- PS 5.1 quirk: `@(ConvertFrom-Json ...)` nests the array. assign first,
  wrap after.
- Keep scripts ascii. PS 5.1 reads bom-less utf-8 as ANSI.

## Layout
- Per-app folders hold a config + short README. Fresh-install only deploys
  (`Copy-Fresh`), never overwrite a lived-in config.
- `Setup.cmd` at the root: one-click, self-elevating wrapper. runs the
  installer with `-Unattended`, extra flags pass through.
- `OOSU/` holds the titus cfg. `OOSHUTUP10.exe` (85MB) is not committed to github. drop it in
  locally or the installer logs a skip and runs without O&O.
  Runs `/quiet` before our reg values so ours win overlaps.
- `ventoy/script/Win-Iot-unattended.xml` is the answer file used with Ventoy.
  `templates/` and `ISO/` are gone. no ISO build step remains.
- No secrets in the tree: blank passwords, empty API keys.

## Agent workflow
- Read the folder README before touching an app config. Most have a 2-minute note that matters.
- Small diffs. One concern per change. Don't reformat files you aren't editing.
- Before saying done: run the syntax parse above, then `install-Win-Iot.ps1 -DryRun`.
  Report what actually ran.
- If a check can't run here, say so. Don't claim it passed.
- Don't commit, push or delete unless asked. `/commit` drafts the message, the human runs it.
- Don't touch the pins in `config/hashes.json`.
- `Copy-Config` overwrites, `Copy-Fresh` keeps. pick on purpose. anything with a blank
  identity or a user's own edits is fresh-only (that is why `.gitconfig` is).
- A script-level call must sit below the function it calls. Keep that ordering.
- WMI class names use underscores (`Win32_Battery`). the hyphen version threw and a catch hid it.
- OpenCode: never turn an MCP server on for every agent. gate it per agent (see docs/OPENCODE.md).
  every enabled tool is sent on every message. measure with tools/token-audit/oc_token_audit.py.
- When a rule here and a guess disagree, the rule wins. If the rule looks wrong, ask.
