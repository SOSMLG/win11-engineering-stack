# Windows Terminal

`Install.ps1 -Profile iot` installs `Microsoft.WindowsTerminal` on builds that
support it and drops `settings.json` into
`%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\`
on a fresh install only. The daily theme module keeps the same scheme on an
existing installation without replacing your profile list.

What it sets:

- default profile: Windows PowerShell 5.1. Command Prompt is the other profile.
  The stale PowerShell 7 entry is gone.
- one Graphite Amber scheme, JetBrains Mono Nerd Font Mono 11, 10k scrollback,
  padding 8, start in `%USERPROFILE%`.
- no acrylic, no transparency, no custom actions.

If the terminal already ran once, the IoT file loses under the fresh-only rule.
Edit by hand, or re-run with `-ConfigsOnly` to overwrite it.
