# Mem Reduct

Optional app in the IoT profile. Added with `-IncludeOptional`. Winget ID:
`Henry++.MemReduct`. The app needs admin rights for its Native API cleanup.

## Config

`memreduct.ini` is copied fresh-only to:

```text
%APPDATA%\Henry++\Mem Reduct\memreduct.ini
```

The repo ships a comment-only file. Mem Reduct writes its own settings there on
first run, so the config stays valid across versions. No registry edits, no
password, no machine-specific path.

## Behavior

- No autostart.
- No interval cleanup.
- No threshold cleanup.
- Native light UI.

This is a tray monitor you open by hand. It is not a tweak pass or a debloat
tool, and it does not touch Defender.
