# quickstart

one front door, two profiles. run PowerShell as a normal user. the script
elevates itself when a step needs it.

## 1. preview the write set

```powershell
.\Install.ps1 -Profile daily -DryRun
.\Install.ps1 -Profile iot -DryRun
```

`-DryRun` prints planned writes, downloads, and installs. it does not change
system settings, installs, or config files. logs and a report are still written.
read the output before the real run.

## 2. run a profile

```powershell
.\Install.ps1 -Profile daily
.\Install.ps1 -Profile iot
```

`daily` is the modular engineering workstation. `iot` is the slim LTSC build.
both use the same `config/` tree. `Setup.cmd` still starts the IoT path for the
old one-click flow.

## 3. verify without writing

```powershell
.\Validate.ps1 -Profile daily
.\Validate.ps1 -Profile iot
```

exit 0 means the checked state is present. exit 1 means at least one real check
failed. host-only misses are reported as `FAIL` or `WARN` and do not change the
machine.

## common filters

```powershell
.\scripts\Install.ps1 -Only os,apps -SxsPath D:\sources\sxs
.\scripts\Install.ps1 -Only engineering -TiaInstaller D:\TIA\Start.exe -MatlabInstaller D:\MATLAB\setup.exe
.\scripts\Install.ps1 -Resume
```

`install-Win-Iot.ps1 -?` lists the full IoT flag set. useful ones are
`-Unattended`, `-ConfigsOnly`, `-OfflineDir`, `-NoWingetBootstrap`,
`-DriverDir`, `-Only`, `-SkipApps`, and `-Fixes`.

## where to go next

- [CLI contract](docs/CLI.md) for front doors and flag meanings
- [runbook](docs/RUNBOOK.md) for run order and manual steps
- [security](SECURITY.md) for image assumptions and secrets
- [OpenCode notes](docs/OPENCODE.md) for provider config
- [visual standard](https://github.com/SOSMLG/.github/blob/main/docs/THEME.md)
