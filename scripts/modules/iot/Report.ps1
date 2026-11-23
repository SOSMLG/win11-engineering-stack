# ---------- 6. report ----------

# machine-readable run report. one json, easy to diff between runs.
try {
  $report = [ordered]@{
    stamp     = $Stamp
    mode      = if ($ConfigsOnly) { 'configs-only' } else { 'full' }
    dryRun    = [bool]$DryRun
    admin     = [bool]$isAdmin
    online    = [bool]$online
    os        = if ($osInfo) {
      $osName = if ($osInfo.PSObject.Properties['Caption']) { $osInfo.Caption } elseif ($osInfo.PSObject.Properties['ProductName']) { $osInfo.ProductName } else { 'unknown' }
      $osBuild = if ($osInfo.PSObject.Properties['BuildNumber']) { $osInfo.BuildNumber } elseif ($osInfo.PSObject.Properties['Build']) { $osInfo.Build } else { '' }
      "$osName build $osBuild"
    } else { 'unknown' }
    phases    = $script:phaseTimes
    installed = $installed
    failed    = $failed
    warnings  = $script:warnCount
    log       = $LogFile
  }
  $reportPath = Join-Path $LogDir "report-$Stamp.json"
  ($report | ConvertTo-Json -Depth 4) | Set-Content -Path $reportPath -Encoding UTF8 -EA Stop
  Log "Report: $reportPath"
} catch { Log "  WARN report: $_" }
Log '---'
if ($failed.Count) { Log ('FAILED/RETRY: ' + ($failed -join ', ')) } elseif (-not $ConfigsOnly) { Log 'All installs reported ok.' }
# one-line scoreboard, then per-phase seconds. details are in the log already.
Log ("summary: $(if ($DryRun) { 'dry-run, ' })installed $($installed.Count), failed $($failed.Count), warnings $($script:warnCount)")
foreach ($p in $script:phaseTimes.Keys) { Log ("  {0}: {1}s" -f $p, $script:phaseTimes[$p]) }
# success means caches are dead weight on a small disk. failures keep them for retry.
if ((-not $ConfigsOnly) -and (-not $DryRun) -and ($failed.Count -eq 0)) {
  foreach ($c in @('winget-bootstrap','github-dl','direct-dl')) {
    Remove-Item (Join-Path $env:TEMP $c) -Recurse -Force -EA SilentlyContinue
  }
  Log '  installer caches purged.'
}
Log "Log: $LogFile"
if ($DryRun) { Log 'Dry-run finished. system state was not changed; logs and the report were written.' }
elseif ($ConfigsOnly) { Log 'Configs-only done.' }
else {
Log 'NEXT:'
Log '  1. reboot, stock desktop as-is.'
Log '  2. double-click Desktop Win-Iot-Finish.cmd (opencode auth + optional password).'
Log '  3. MATLAB via campus license + USB-serial drivers (CH340/CP210x/ST-Link) manually.'
Log '  4. set LibreWolf as default browser in Settings > Apps > Default apps.'
}
if ($Reboot -and -not $DryRun) {
  Log 'rebooting in 60s (-Reboot). save your stuff.'
  shutdown /r /t 60 /c 'Win-Iot setup done. rebooting.' 2>&1 | Out-Null
}
if ($Reboot -and $DryRun) { Log 'reboot skipped (dry-run).' }
if ($transcriptOn) { try { Stop-Transcript | Out-Null } catch {} }
