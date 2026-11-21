# AGENTS.md

## What this is

One Windows setup repo with two profiles:

- `daily`: `scripts/Install.ps1`, modular, engineering workstation.
- `iot`: `install-Win-Iot.ps1`, slim Win10/Win11 IoT LTSC build.

`Install.ps1` and `Validate.ps1` are the front doors. `config/` is the only
config tree. Docs live in `docs/`. Ventoy answer files live in `ventoy/script/`.

## Rules learned the hard way

- Native exes do not throw in PowerShell. Check `$LASTEXITCODE`.
- `winget download` filenames embed the installer tech. Read the tech for
  silent flags instead of guessing.
- Keep scripts ascii. Windows PowerShell 5.1 reads bom-less UTF-8 as ANSI.
- No `??`, `?.`, or ternary operators. PS 5.1 comes first.
- Add a dry-run line for every new write. `Complete-Phase` never marks done in
  dry-run.
- Per-app configs are fresh-only unless a deliberate overwrite is wanted.
  `Copy-Config` overwrites, `Copy-Fresh` keeps.
- Shell profile hooks are all `Get-Command` guarded. Keep that guard.
- VSCodium theme folders must match `publisher.name-version`.
- `@(ConvertFrom-Json ...)` nests arrays in PS 5.1. Assign first, wrap after.
- A script-level call sits below the function it calls.
- Keep WMI class names with underscores, for example `Win32_Battery`.
- Defender stays Microsoft Defender. Use `Add-MpPreference` for exclusions.
  Never use `Set-MpPreference`. Never disable real-time protection.
- `OMNIROUTE_API_KEY` stays in the environment. No key goes into a file.
- OmniRoute logon tasks go through a `.cmd` wrapper because the CLI can resolve
  to a `.cmd` shim.
- Voice: short lowercase asides, no em dashes, no buzzwords. Do not "improve"
  wording in a way that touches logic.

## Verification

Parse every PowerShell file, parse every JSON file, then run the read-only
paths:

```powershell
Get-ChildItem .\scripts -Recurse -Filter *.ps1 | ForEach-Object {
  $t = $null; $e = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$t, [ref]$e)
  if ($e.Count) { $e | ForEach-Object { Write-Error $_.Message } }
}
.\Install.ps1 -Profile daily -DryRun
.\Install.ps1 -Profile iot -DryRun
.\Validate.ps1 -Profile daily
.\Validate.ps1 -Profile iot
```

Report only what actually ran. If a check cannot run here, say so.

## Safety

- Never edit `C:\Program Files\Siemens`, `C:\Program Files\MATLAB`, or user
  datasets unless the task explicitly asks.
- No public-profile firewall rules for PLC traffic.
- No secrets in the tree. Blank passwords and empty API keys only.
- Small diffs. One concern per change. Do not reformat files you are not editing.
