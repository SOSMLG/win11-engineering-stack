# ---------- 5. defaults and finish helper, stock panel untouched ----------
if ((-not $ConfigsOnly) -and (Should-Run 'autostart')) {
Log 'Autostart...'
Start-Phase 'autostart'
# default browser is a Windows UserChoice action. print the step, never force it.
if ($DryRun) { Log '  [dry-run] would print the LibreWolf default-browser step.' }
else { Log '  set LibreWolf as default browser in Settings > Apps > Default apps.' }

# auth can't run unattended, so it goes on the desktop as a double-click thing.
if ($DryRun) { Log '  [dry-run] would write Desktop Win-Iot-Finish.cmd.' }
else {
try {
  $finishCmd = '@echo off' + "`r`n" + 'title Win-Iot finish setup' + "`r`n" +
    'powershell -NoProfile -ExecutionPolicy Bypass -Command "opencode auth login"' + "`r`n" +
    'echo.' + "`r`n" + 'echo Set a password now if you want one (Enter twice to stay blank):' + "`r`n" +
    'net user "My Pc" *' + "`r`n" +
    'echo.' + "`r`n" + 'echo Delete this shortcut when finished.' + "`r`n" + 'pause'
  $finishPath = Join-Path ([Environment]::GetFolderPath('CommonDesktopDirectory')) 'Win-Iot-Finish.cmd'
  Set-Content -Path $finishPath -Value $finishCmd -Encoding Ascii -Force -EA Stop
  Log "  finish helper: $finishPath"
} catch { Log "  WARN finish helper: $_" }
}
Stop-Phase
Complete-Phase 'autostart'
} else { Log 'Autostart/browser/finish skipped (configs-only).' }

if (-not $ConfigsOnly) {
  if ($DryRun) { Log 'Self-check skipped (dry-run).' }
  else {
  Log 'Self-check...'
  foreach ($s in @(
    @{ n='git'; cmd={ git --version } },
    @{ n='python'; cmd={ python --version } },
    @{ n='node'; cmd={ node --version } },
    @{ n='codium'; cmd={ & (Get-CmdPath 'codium') --version } },
    @{ n='opencode'; cmd={ opencode --version } },
    @{ n='7zip'; cmd={ if (-not (Get-Command 7z -EA SilentlyContinue) -and -not (Test-Path 'C:\Program Files\7-Zip\7z.exe')) { throw '7-Zip not found' } } }
  )) {
    if ((Invoke-Native $s.cmd) -eq 0) { Log "  smoke ok: $($s.n)" }
    else { Log "  smoke MISSING: $($s.n)" }
  }
  }
}
