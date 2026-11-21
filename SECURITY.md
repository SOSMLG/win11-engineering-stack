# security

## what this repo does
the installer changes system settings and installs software. it does not apply
tweaks, debloat Windows, or change Defender preferences. run `-DryRun` and try a
VM first.

## what to know before running it
- `Setup.cmd` self-elevates. the installer is normally run with `-ExecutionPolicy Bypass`. without
  `-Unattended` it also sets the CurrentUser execution policy to RemoteSigned.
- **downloads are not hash-pinned.** `config/hashes.json` is empty. `-SkipHashVerify`
  exists, but there is nothing pinned to skip right now.
- **bounded package sources.** the IoT installer uses staged files, winget, GitHub
  releases, and direct vendor URLs. it does not bootstrap a third-party package manager.
- **the answer files** (`ventoy/script/*.xml`) create a local administrator
  named `My Pc` with a **blank password** and log it in once automatically. Windows normally limits
  blank-password accounts to console logon, but set a password after first boot if the machine
  leaves the bench.
- OpenCode uses the OmniRoute provider in `config/opencode/opencode.json`. set
  `OMNIROUTE_API_KEY` as a user environment variable; the repo never stores it.
- no secrets live in the tree. passwords and API keys are blank.

## reporting a problem
use GitHub's private vulnerability reporting (Security tab, "Report a vulnerability") instead of a
public issue. include the commit, the command you ran, and what you saw.

## supported versions
the latest commit on `main` and the latest tagged release.
