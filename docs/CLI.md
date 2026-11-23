# CLI contract

two front doors, two profiles. flags not declared on the front door pass through
to the profile script unchanged.

| command | profile | target |
| --- | --- | --- |
| `Install.ps1 -Profile daily` | daily | `scripts/Install.ps1` |
| `Install.ps1 -Profile iot` | iot | `scripts/Install.ps1 -Profile iot` |
| `Install.ps1 -Profile daily -Verify` | daily | `Validate.ps1 -Profile daily` |
| `Install.ps1 -Profile iot -Verify` | iot | `Validate.ps1 -Profile iot` |
| `Install.ps1 -Profile daily -Status` | daily | saved daily state only |
| `Validate.ps1` | daily | `scripts/Validate.ps1` |
| `Validate.ps1 -Profile iot` | iot | `scripts/Install.ps1 -Profile iot -Verify` |

`Install.ps1 -Verify` is an alias for the matching validator. Neither validation
path writes settings, state, logs, transcripts, or reports. `Setup.cmd` always
starts the IoT profile through `Install.ps1` with `-Unattended` before any extra
flags you pass.

## common flags

| flag | daily | iot | meaning |
| --- | --- | --- | --- |
| `-DryRun` | yes | yes | plan without applying system changes |
| `-Only` | module names | app ID patterns | filters work |
| `-Force` | yes | yes | rerun skipped work and overwrite managed files |
| `-Verify` | yes | yes | read-only state check through the front door |
| `-Status` | yes | no | print saved state and the next command |
| `-Resume` | yes | no | continue after a pending reboot |
| `-ConfigsOnly` | no | yes | copy configs only |
| `-OfflineDir` | no | yes | staged install source |
| `-SkipApps` | no | yes | skip app install phase |

daily `-Only` accepts `preflight`, `os`, `packages`, `apps`, `engineering`,
`developer`, `omniroute`, `theme`, `configs`, `validate`, or `all`.

iot `-Only` and `-SkipApps` match app IDs as substrings. They do not gate
configs, drivers, repairs, or other phases.

## order and state

daily module load order is alphabetical from `scripts/modules/`. Run order is
fixed in `scripts/Install.ps1`:

```text
preflight os packages apps engineering developer omniroute theme configs validate
```

Daily state lives in `%LOCALAPPDATA%\win11-stack\state.json`. IoT state lives
under the `StateDir` path and uses `phases.json` plus `apps.json`. The two state
systems are separate by design.

Dry-run does not write state. Daily still writes its log and transcript. IoT
also writes a report JSON. A real run prints a summary with `ok`, `skip`, `warn`,
and `fail` counts, then the next command. A module can mark itself failed; that
sets the exit code and stops the run from claiming the module completed.

## exit codes

- `0` means the checked path completed without a hard failure.
- `1` means at least one real check failed.
- a nonzero child exit code is propagated by both front doors.
- the UAC relaunch waits for the elevated child and returns its exit code.

Host-only misses such as a missing Defender service, S7 firewall rule, or font
are real `FAIL` results on this machine. They are reported, not repaired.
Defender preferences are never written by this repo.

## safety notes

- `OMNIROUTE_API_KEY` is read from the environment only. It is never written to a file.
- dry-run skips the execution policy write.
- IoT log, state, transcript, and report setup happens after `-Verify`, so the read-only path writes nothing.
- LibreWolf default browser is a manual Windows UserChoice step.
- no published tag is moved by installer runs.
