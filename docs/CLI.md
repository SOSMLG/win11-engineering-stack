# CLI contract

two front doors, two profiles. extra flags after `-Profile` pass through to the
profile script unchanged.

| command | profile | target |
| --- | --- | --- |
| `Install.ps1 -Profile daily` | daily | `scripts/Install.ps1` |
| `Install.ps1 -Profile iot` | iot | `install-Win-Iot.ps1` |
| `Validate.ps1 -Profile daily` | daily | `scripts/Validate.ps1` |
| `Validate.ps1 -Profile iot` | iot | `install-Win-Iot.ps1 -Verify` |

`Setup.cmd` always starts the IoT script with `-Unattended` before any extra
flags you pass.

## common flags

| flag | daily | iot | meaning |
| --- | --- | --- | --- |
| `-DryRun` | yes | yes | plan without applying system changes |
| `-Only` | module names | app ID patterns | filters work |
| `-Force` | yes | yes | rerun skipped work |
| `-Verify` | via `Validate.ps1` | yes | read-only state check |
| `-Resume` | yes | no | continue after a pending reboot |
| `-ConfigsOnly` | no | yes | copy configs only |
| `-OfflineDir` | no | yes | staged install source |
| `-SkipApps` | no | yes | skip app install phase |

daily `-Only` accepts `preflight`, `os`, `packages`, `apps`, `engineering`,
`developer`, `omniroute`, `theme`, `configs`, `validate`, or `all`.

iot `-Only` and `-SkipApps` match app IDs as substrings. they do not gate
configs, drivers, repairs, or other phases.

## order and state

daily module load order is alphabetical from `scripts/modules/`. run order is
fixed in `scripts/Install.ps1`:

```text
preflight os packages apps engineering developer omniroute theme configs validate
```

daily state lives in `%LOCALAPPDATA%\win11-stack\state.json`. iot state lives
under the `StateDir` path and uses `phases.json` plus `apps.json`. the two state
systems are separate by design.

dry-run does not write state. it still writes logs and, for iot, a report JSON.

## exit codes

- `0` means the checked path completed without a hard failure.
- `1` means at least one real check failed.
- a nonzero child exit code is propagated by both front doors.

host-only misses such as a missing Defender service, S7 firewall rule, or font
are real `FAIL` results on this machine. they are reported, not repaired.
Defender preferences are never written by this repo.

## safety notes

- `OMNIROUTE_API_KEY` is read from the environment only. it is never written to a file.
- dry-run skips the execution policy write.
- IoT `-Verify` writes a log directory and transcript before the read-only check.
- no published tag is moved by installer runs.
