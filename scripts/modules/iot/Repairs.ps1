# ---------- 0. repairs. opt-in only (-Fixes), runs before everything. ----------
if ($Fixes) {
  Log 'Repairs...'
  Start-Phase 'repairs'
  if ($DryRun) {
    Log '  [dry-run] would flush dns, restart Dnscache/NlaSvc, reset winsock, park the update caches.'
  } else {
    $exit = Invoke-Native { ipconfig /flushdns }
    if ($exit -eq 0) { Log '  dns cache flushed.' } else { Log "  WARN flushdns exit=$exit" }
    try {
      foreach ($svc in @('Dnscache','NlaSvc')) {
        if (Get-Service $svc -EA SilentlyContinue) { Restart-Service $svc -Force -EA Stop; Log "  svc restarted: $svc" }
      }
    } catch { Log "  WARN net services: $_" }
    $exit = Invoke-Native { netsh winsock reset }
    if ($exit -eq 0) { Log '  winsock reset (needs the reboot at the end).' } else { Log "  WARN winsock exit=$exit" }
    if ($isAdmin) {
      # update stack reset. stops services, parks the caches aside, starts over.
      try {
        foreach ($svc in @('wuauserv','bits','cryptsvc')) { Stop-Service $svc -Force -EA SilentlyContinue }
        foreach ($d in @('C:\Windows\SoftwareDistribution','C:\Windows\System32\catroot2')) {
          if ((Test-Path $d) -and -not (Test-Path "$d.bak")) { Rename-Item $d "$d.bak" -Force -EA Stop; Log "  parked: $d" }
        }
        foreach ($svc in @('cryptsvc','bits','wuauserv')) { Start-Service $svc -EA SilentlyContinue }
        Log '  update stack reset.'
      } catch { Log "  WARN update reset: $_" }
    } else { Log '  update reset needs admin. skipped.' }
  }
  Stop-Phase
  Complete-Phase 'repairs'
}

. (Join-Path $Repo 'scripts\modules\iot\Packages.ps1')
. (Join-Path $Repo 'scripts\modules\iot\Helpers.ps1')
