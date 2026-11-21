# OpenCode on this box

two configs, kept apart on purpose:

- `config/opencode/opencode.json` is **deployed** by the installer to `~\.config\opencode\opencode.json`. this is the everyday setup.
- `config/AGENTS.global.md` is deployed as `~\.config\opencode\AGENTS.md`. it is a managed block, so your own rules outside the block survive.
- `opencode.json` at the repo root only configures OpenCode while you work **on this repo**. it inherits everything else from the deployed config.

both use the V2 `providers` shape. `OMNIROUTE_API_KEY` stays in the environment. no key is written to a file.

## everyday config

- model: `omniroute/auto-coding`
- provider: `omniroute` at `http://127.0.0.1:20128/v1`
- models: `auto`, `auto-coding`, `auto-fast`
- deny rules live in `permissions`: Siemens, MATLAB, datasets, `.venv`, SSH, KeePass, and `.env`
- shell commands ask first; git status, diff, log, and show run freely
- watcher ignores are in `watcher.ignore`

no MCP server is enabled by default. that keeps each message small and avoids sending unused tool definitions.

## repo-only commands

- `/precheck` parses every PowerShell file in this repo
- `/dryrun` runs `Install.ps1 -Profile iot -DryRun`

## upgrading an existing machine

the installer is fresh-only, so a machine that already has `~\.config\opencode\opencode.json` keeps its old config. to switch: back it up, then run `install-Win-Iot.ps1 -ConfigsOnly`, or copy `config/opencode/opencode.json` over by hand.

## measure your own setup

`tools/token-audit/oc_token_audit.py` runs a local fake model and reports what OpenCode sends per message, per tool, and per MCP server. nothing leaves the machine and no key is needed.

```powershell
python tools\token-audit\oc_token_audit.py
python tools\token-audit\oc_token_audit.py --cwd C:\proj
```

the first run may take a while if it has to fetch MCP packages.
