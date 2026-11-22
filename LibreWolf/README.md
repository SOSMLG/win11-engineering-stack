# LibreWolf

The browser in the IoT profile is `LibreWolf.LibreWolf`. It is in the core app
list. The installer is used, not the portable launcher.

## What the script places

- `%USERPROFILE%\.librewolf\librewolf.overrides.cfg`, fresh-only.
- Three profiles under `%APPDATA%\LibreWolf\Profiles`: `personal`, `uni`, `social`.
- Start Menu shortcuts that open each profile with `-P <name> -no-remote`.

The overrides file uses `defaultPref`, so anything you change in the UI wins on
the next run. LibreWolf ships hardened. This file only sets startup behavior and
an explicit warning before closing several tabs. No site-breaking prefs.

## What stays manual

Windows 11 protects the default browser choice. The script prints the step
instead of forcing it:

```text
Settings > Apps > Default apps > Web browser > LibreWolf
```

Sign in to each profile separately. Do not reuse a personal account in the uni
or social profile.

## Theme

LibreWolf keeps its native light UI. Engineering apps stay native light; only
Windows Terminal and VSCodium use Graphite Amber.
