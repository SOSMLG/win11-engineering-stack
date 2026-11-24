# quickstart

one front door, two profiles. run PowerShell as a normal user. the script
elevates itself when a step needs it.

## 1. preview the write set

```powershell
.\Install.ps1 -Profile daily -DryRun
.\Install.ps1 -Profile iot -DryRun
```

`-DryRun` prints planned writes, downloads, and installs. it does not change
system settings, installs, or config files. daily still writes its log and
transcript; iot also writes a report. read the output before the real run.

## 2. run a profile

```powershell
.\Install.ps1 -Profile daily
.\Install.ps1 -Profile iot
```

`daily` is the modular engineering workstation. `iot` is the slim post-install
build for tiny11, AspectOS, and Windows 11 IoT Enterprise LTSC. both use the
same `config/` tree. `Setup.cmd` starts the IoT profile through `Install.ps1`
for the one-click flow and exits clean when it succeeds.

## 3. verify without writing

```powershell
.\Install.ps1 -Profile daily -Verify
.\Install.ps1 -Profile iot -Verify
```

`-Verify` on the front door calls the matching validator. you can also call
`Validate.ps1` directly; it defaults to `daily`. exit 0 means the checked state
is present. exit 1 means at least one real check failed. neither path writes a
log, transcript, report, or setting.

## 4. read daily state

```powershell
.\Install.ps1 -Profile daily -Status
```

`-Status` prints completed modules, pending reboot, and the next command. it
reads the saved state file only.

## common filters

```powershell
.\Install.ps1 -Profile daily -Only os,apps -SxsPath D:\sources\sxs
.\Install.ps1 -Profile daily -Only engineering -TiaInstaller D:\TIA\Start.exe -MatlabInstaller D:\MATLAB\setup.exe
.\Install.ps1 -Profile daily -Resume
.\Install.ps1 -Profile iot -ConfigsOnly
```

`Install.ps1 -Profile iot -?` lists the full IoT flag set. useful ones are
`-Unattended`, `-ConfigsOnly`, `-OfflineDir`, `-NoWingetBootstrap`,
`-DriverDir`, `-Only`, `-SkipApps`, `-Minimal`, and `-NoDebloat`. Optional apps
(Joplin, Spotube, Mem Reduct) are included unless `-Minimal` is set. The single
default debloat pass runs on every normal install; `-NoDebloat` is the recovery
switch.

## where to go next

- [app inventory](docs/APPS.md) for install IDs, config paths, and manual steps
- [CLI contract](docs/CLI.md) for front doors and flag meanings
- [runbook](docs/RUNBOOK.md) for run order and manual steps
- [security](SECURITY.md) for image assumptions and secrets
- [OpenCode notes](docs/OPENCODE.md) for provider config
- [visual standard](https://github.com/SOSMLG/.github/blob/main/docs/THEME.md)
