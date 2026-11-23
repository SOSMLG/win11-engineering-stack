$ErrorActionPreference = 'Continue'
Set-StrictMode -Version 2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Repo = $script:RepoRoot
# -ConfigsOnly re-deploys user configs (VSCodium, Vesktop, qBittorrent, opencode,
# terminal, ...) and nothing else. install phases are gated below.
# log, state, and transcript start after -Verify, so the read-only path writes nothing.
# warn count lands in the run report. it is the number a tired human reads first.
$script:warnCount = 0
. (Join-Path $Repo 'scripts\modules\iot\Core.ps1')
$isAdmin = Test-Admin

# -Verify: read-only check of configs and installed state. no writes.
if ($Verify) {
  Log 'Verify: checking configs and installed state (no changes)...'
  $miss = 0
  $repoFiles = @(
    'config\defaults.json',
    'config\hashes.json',
    'config\opencode\opencode.json',
    'config\vscodium\settings.json',
    'config\vesktop\settings.json',
    'config\vencord\settings.json'
  )
  foreach ($rel in $repoFiles) {
    $target = Join-Path $Repo $rel
    if (-not (Test-Path $target)) { Log "  MISS: $rel missing"; $miss++; continue }
    try { [void](Get-Content $target -Raw | ConvertFrom-Json); Log "  ok: $rel" }
    catch { Log "  MISS: $rel is not valid JSON"; $miss++ }
  }

  $vsSet = Join-Path $env:APPDATA 'VSCodium\User\settings.json'
  if (Test-Path $vsSet) {
    try {
      $vsJson = Get-Content $vsSet -Raw | ConvertFrom-Json
      $themeProp = $vsJson.PSObject.Properties['workbench.colorTheme']
      $theme = if ($null -eq $themeProp) { '' } else { [string]$themeProp.Value }
      if ($theme -eq 'Graphite Amber') { Log '  ok: vscodium graphite amber theme' }
      else { Log "  MISS: vscodium theme is $theme"; $miss++ }
    } catch { Log "  MISS: vscodium settings are not valid JSON"; $miss++ }
  } else { Log '  skip: vscodium settings not applied yet' }

  $oc = Join-Path $env:USERPROFILE '.config\opencode\opencode.json'
  if (Test-Path $oc) {
    try {
      $ocJson = Get-Content $oc -Raw | ConvertFrom-Json
      if (($ocJson.PSObject.Properties.Name -contains 'providers') -and ($ocJson.PSObject.Properties.Name -notcontains 'provider')) {
        Log '  ok: opencode V2 config'
      } else { Log '  MISS: opencode config is not on the V2 providers shape'; $miss++ }
    } catch { Log '  MISS: opencode config is not valid JSON'; $miss++ }
  } else { Log '  skip: opencode config not applied yet' }

  $listeners = @(Get-NetTCPConnection -LocalPort 20128 -State Listen -EA SilentlyContinue)
  if ($listeners.Count -gt 0) {
    $public = @($listeners | Where-Object { $_.LocalAddress -notin @('127.0.0.1', '::1') })
    if ($public.Count -eq 0) { Log '  ok: OmniRoute bound to loopback only' }
    else { Log '  MISS: OmniRoute is listening on a public address'; $miss++ }
  } else { Log '  skip: OmniRoute is not listening yet' }

  if ($miss) { Log "Verify: $miss thing(s) missing." } else { Log 'Verify: all good.' }
  exit $(if ($miss) { 1 } else { 0 })
}

$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
# C:\Windows\Logs needs admin. non-admin runs fall back to TEMP instead of dying.
try { New-Item -ItemType Directory -Force -Path $LogDir -EA Stop | Out-Null }
catch { $LogDir = Join-Path $env:TEMP 'Win-Iot-Setup'; New-Item -ItemType Directory -Force -Path $LogDir -EA SilentlyContinue | Out-Null }
# non-admin runs land in TEMP, so the state dir follows the log dir there.
if ($StateDir -eq 'C:\Windows\Logs\Win-Iot-Setup\state' -and $LogDir -ne 'C:\Windows\Logs\Win-Iot-Setup') { $StateDir = Join-Path $LogDir 'state' }
$LogFile = Join-Path $LogDir "install-$Stamp.log"
$transcriptOn = $false
try { Start-Transcript -Path $LogFile -Force -EA Stop | Out-Null; $transcriptOn = $true } catch {}

# one-shot Win-Iot-Setup task already fired. remove it so it never refires.
if ($DryRun) { Log '  [dry-run] would remove the one-shot Win-Iot-Setup scheduled task.' }
else { try { Unregister-ScheduledTask -TaskName 'Win-Iot-Setup' -Confirm:$false -EA Stop } catch {} }
if (-not $isAdmin) { Log 'WARN: not admin. fonts and autostart will probably fail.' }

# os + hardware. keeps edition/ltsc/arch detect + optional hw gate.
# declared out here so the run report can read it even if the probe throws.
$osInfo = $null
try {
  $b = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuild
  Log "OS build: $b"
  if (Get-Command Get-OSInfo -EA SilentlyContinue) { $osInfo = Get-OSInfo }
  if ($osInfo) {
    Log ("OS: {0} {1} ({2}) arch={3}" -f $osInfo.ProductName, $osInfo.Version, $osInfo.Build, $osInfo.Architecture)
    $family = if ($osInfo.IsWin11) { 'Win11' } else { 'Win10' }
    # name the ltsc family plainly so a 10 box and an 11 box both read right.
    if ($osInfo.IsWin10LTSC -or $osInfo.IsWin11LTSC) { Log "  $family LTSC/IoT detected ($($osInfo.Build))." }
    elseif ($osInfo.IsLTSC -or $osInfo.IsIoT) { Log "  LTSC/IoT edition detected ($family $($osInfo.Build))." }
    else { Log "  WARN: not an LTSC/IoT edition ($family $($osInfo.Build)). going ahead anyway." }
  }
  # known ltsc builds: 17763 = win10 iot ltsc 2019, 19044 = win10 iot ltsc 2021,
  # 26100 = win11 (iot) enterprise ltsc 2024. anything else, warn + keep going.
  $knownLtsc = @('17763', '19044', '26100')
  if ($osInfo -and ($osInfo.IsLTSC -or $osInfo.IsIoT) -and ($knownLtsc -notcontains [string]$b)) { Log "WARN: LTSC build $b not in known list. going ahead anyway, watch the log." }
} catch { Log "WARN: OS check failed: $_" }

# arch gate: this repo assumes x64. warn loudly if someone runs it on arm32.
if ($env:PROCESSOR_ARCHITECTURE -and $env:PROCESSOR_ARCHITECTURE -ne 'AMD64') {
  Log "WARN: PROCESSOR_ARCHITECTURE=$env:PROCESSOR_ARCHITECTURE, repo is x64-only. downloads may not match."
}
if ($Arch -and $Arch -ne 'x64' -and $Arch -ne 'amd64') { Log "WARN: -Arch $Arch given, x64 is the only tested target." }

# optional hardware sanity. never blocks, just reports so you know before a 20 min run.
if ($DetectHardware -and (Get-Command Test-HardwareMin -EA SilentlyContinue)) {
  $hw = Test-HardwareMin
  if ($hw.OK) { Log ("Hardware: {0} / {1} GB RAM" -f $hw.CPU, $hw.MemoryGB) }
  else { Log 'WARN: hardware detection failed (wmi gutted?).' }
}

if ((-not $Unattended) -and (-not $DryRun)) {
  try { Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -EA SilentlyContinue } catch {}
}

# no net + no OfflineDir means nothing to install. say so now, not 20 min in.
# probe ip is just a beacon, works even when dns is broken.
$netProbe = '1.1.1.1'
$online = $false
try { $online = Test-Connection -ComputerName $netProbe -Count 1 -Quiet -EA Stop } catch {}
if (-not $online -and -not $OfflineDir) {
  Log 'WARN: no network detected and no -OfflineDir given.'
  Log '  plug phone in for usb tethering, or stage installers in a folder on an online PC'
  Log "  and re-run with: -OfflineDir '<path-to-Offline>' -Unattended"
}
if (-not $online) { Log 'OFFLINE mode: online engines skipped; pre-seeded files still apply.' }

# fresh boot almost never has DHCP yet. usb tethering takes a few min to enable,
# so wait up to 10 min or winget dies for no reason.
# dry-run installs nothing, so it skips the wait too.
if ((-not $online) -and (-not $ConfigsOnly) -and (-not $DryRun)) {
  $waited = 0
  while (-not $online -and $waited -lt 600) {
    Start-Sleep -Seconds 15; $waited += 15
    try { $online = Test-Connection -ComputerName $netProbe -Count 1 -Quiet -EA Stop } catch {}
  }
  if ($online) { Log "network up after ${waited}s." }
  else { Log 'WARN: still offline after 10 min - continuing with pre-seeded files only.' }
}

# preflight: cheap checks now beat a 20 min run dying at download #7.
try {
  $sysDrive = Get-PSDrive ($env:SystemDrive -replace ':','') -EA Stop
  $freeGB = [math]::Round($sysDrive.Free / 1GB, 1)
  if ($freeGB -lt 1.5) { Log "WARN: only $freeGB GB free on $env:SystemDrive. installs will likely fail." }
  elseif ($freeGB -lt 4) { Log "WARN: $freeGB GB free on $env:SystemDrive. tight for downloads + installs." }
  else { Log "disk: $freeGB GB free on $env:SystemDrive." }
} catch { Log "WARN: disk check: $_" }
if ($OfflineDir) {
  if (-not (Test-Path $OfflineDir)) { Log "WARN: -OfflineDir not found: $OfflineDir" }
  else {
    $staged = @(Get-ChildItem $OfflineDir -Recurse -File -EA SilentlyContinue)
    if ($staged.Count -eq 0) { Log "WARN: -OfflineDir is empty: $OfflineDir" }
    else { Log "offline: $($staged.Count) staged files in $OfflineDir." }
  }
}

. (Join-Path $Repo 'scripts\modules\iot\Repairs.ps1')

. (Join-Path $Repo 'scripts\modules\iot\Configs.ps1')


. (Join-Path $Repo 'scripts\modules\iot\Defaults.ps1')

. (Join-Path $Repo 'scripts\modules\iot\Report.ps1')
