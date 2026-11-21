<#
.SYNOPSIS
  My Win10/Win11 IoT (Enterprise) LTSC setup. Unattended, rerunnable.
.DESCRIPTION
  Built for a tiny10 box with no store and usually no network
  on first boot. PS 5.1, stock Windows desktop, Helium, VSCodium.
  No extra shell, no extra window manager. Stock colors everywhere.
  Engines per app, first hit wins: staged -OfflineDir files, winget,
  choco, github releases. Log lands in C:\Windows\Logs\Win-Iot-Setup either way.
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File install-Win-Iot.ps1
  powershell -ExecutionPolicy Bypass -File install-Win-Iot.ps1 -Unattended -OfflineDir D:\Offline
  powershell -ExecutionPolicy Bypass -File install-Win-Iot.ps1 -Unattended -DriverDir D:\Drivers -Reboot
  powershell -ExecutionPolicy Bypass -File install-Win-Iot.ps1 -IncludeOptional -Unattended
  powershell -ExecutionPolicy Bypass -File install-Win-Iot.ps1 -ConfigsOnly
  (configs-only: re-copy user configs to their real locations, nothing else.)
#>
[CmdletBinding()]
param(
  [switch]$SkipHashVerify,
  [switch]$Idempotent,
  [switch]$Force,
  [string]$StateDir = 'C:\Windows\Logs\Win-Iot-Setup\state',
  [string]$BuildConfig = '',
  [string]$Arch = '',
  [switch]$DetectHardware,
  [switch]$IncludeOptional,
  [switch]$Unattended,
  [switch]$NoWingetBootstrap,
  [switch]$NoChocoBootstrap,
  [string]$OfflineDir = '',
  [string]$LogDir = 'C:\Windows\Logs\Win-Iot-Setup',
  [string]$DriverDir = '',
  [switch]$ConfigsOnly,
  [switch]$Reboot,
  [switch]$Fixes,
  [switch]$DryRun,
  [switch]$Verify,
  [string[]]$Only = @(),
  [string[]]$SkipApps = @()
)
$ErrorActionPreference = 'Continue'
Set-StrictMode -Version 2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Repo = Split-Path $MyInvocation.MyCommand.Path -Parent
# -ConfigsOnly re-deploys user configs (VSCodium, Vesktop, qBittorrent, opencode,
# terminal, ...) and nothing else. install phases are gated below.
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
# C:\Windows\Logs needs admin. non-admin runs fall back to TEMP instead of dying.
try { New-Item -ItemType Directory -Force -Path $LogDir -EA Stop | Out-Null }
catch { $LogDir = Join-Path $env:TEMP 'Win-Iot-Setup'; New-Item -ItemType Directory -Force -Path $LogDir -EA SilentlyContinue | Out-Null }
# non-admin runs land in TEMP, so the state dir follows the log dir there.
if ($StateDir -eq 'C:\Windows\Logs\Win-Iot-Setup\state' -and $LogDir -ne 'C:\Windows\Logs\Win-Iot-Setup') { $StateDir = Join-Path $LogDir 'state' }
$LogFile = Join-Path $LogDir "install-$Stamp.log"
$transcriptOn = $false
try { Start-Transcript -Path $LogFile -Force -EA Stop | Out-Null; $transcriptOn = $true } catch {}
# warn count lands in the run report. it is the number a tired human reads first.
$script:warnCount = 0
function Log($m) {
  if ("$m" -like '*WARN*') { $script:warnCount++ }
  Write-Host ("[{0:HH:mm:ss}] {1}" -f (Get-Date), $m)
}
# phase timers: seconds per phase, straight into the report. cheap and honest.
$script:phaseTimes = [ordered]@{}
$script:phaseName = $null
$script:phaseStart = $null
function Start-Phase($name) { $script:phaseName = $name; $script:phaseStart = Get-Date }
function Stop-Phase {
  if ($script:phaseName) {
    $elapsed = (Get-Date) - $script:phaseStart
    $script:phaseTimes[$script:phaseName] = [int][math]::Round($elapsed.TotalSeconds, 0)
    $script:phaseName = $null
  }
}
function Refresh-Path {
  # fresh installs don't land on PATH in this session. re-read it or python/codium are "missing".
  try { $env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path','User') } catch {}
}

# ---------- phase 0. state, OS + hw detect ----------
# idempotency: one small json per phase under StateDir. a completed phase is
# skipped on re-run unless -Force. a missing state file is never fatal.
function Get-PhaseState {
  if (-not (Test-Path $StateDir)) { return @{} }
  $sf = Join-Path $StateDir 'phases.json'
  if (-not (Test-Path $sf)) { return @{} }
  try { return (Get-Content $sf -Raw | ConvertFrom-Json) } catch { return @{} }
}
function Set-PhaseDone($name) {
  try {
    if (-not (Test-Path $StateDir)) { New-Item -ItemType Directory -Force -Path $StateDir -EA Stop | Out-Null }
    $sf = Join-Path $StateDir 'phases.json'
    $data = @{}
    if (Test-Path $sf) {
      try { $obj = Get-Content $sf -Raw | ConvertFrom-Json; foreach ($p in $obj.PSObject.Properties) { $data[$p.Name] = $p.Value } } catch {}
    }
    $data[$name] = (Get-Date).ToString('o')
    ($data | ConvertTo-Json) | Set-Content -Path $sf -Encoding UTF8 -EA Stop
  } catch { Log "  WARN state write $name`: $_" }
}
function Test-PhaseDone($name) {
  if ($Force) { return $false }
  $st = Get-PhaseState
  if ($st -and ($st.PSObject.Properties.Name -contains $name)) { return $true }
  return $false
}
# idempotency is opt-in (-Idempotent). without it every phase runs like before.
function Should-Run($phase) {
  if (-not $Idempotent) { return $true }
  if (Test-PhaseDone $phase) { Log "  skip (done): $phase"; return $false }
  return $true
}
function Complete-Phase($phase) {
  # dry-run changed nothing, so nothing is done.
  if ($Idempotent -and -not $DryRun) { Set-PhaseDone $phase }
}

# optional sha256 check for downloaded installers. config/hashes.json maps an
# asset name (or glob) to a hex sha256. empty/missing config = nothing checked,
# downloads proceed as before. a mismatch tosses the file so retry re-downloads.
function Get-ExpectedHash($name) {
  if (-not $name) { return $null }
  $hf = Join-Path $Repo 'config\hashes.json'
  if (-not (Test-Path $hf)) { return $null }
  try {
    $map = Get-Content $hf -Raw | ConvertFrom-Json
    foreach ($p in $map.PSObject.Properties) {
      if ($name -like $p.Name) { return [string]$p.Value }
    }
  } catch {}
  return $null
}
function Test-DownloadHash($file) {
  if ($SkipHashVerify) { return $true }
  $exp = Get-ExpectedHash (Split-Path $file.FullName -Leaf)
  if (-not $exp) { return $true }
  try {
    $actual = (Get-FileHash -Algorithm SHA256 -Path $file.FullName -EA Stop).Hash
    if ($actual.ToUpper() -eq $exp.ToUpper()) { Log "  hash ok: $($file.Name)"; return $true }
    Log "  WARN hash MISMATCH $($file.Name): got $actual want $exp - tossing."
    Remove-Item $file.FullName -Force -EA SilentlyContinue
    return $false
  } catch { Log "  WARN hash check $($file.Name): $_"; return $true }
}
# native exes don't throw, and Start-Process never sets $LASTEXITCODE at all
# (verified: stale code survives it). everything native goes through here.
# returns the real exit code, -1 if it never even launched.
function Invoke-Native {
  param(
    [scriptblock]$cmd,
    [object[]]$ArgList
  )
  $LASTEXITCODE = 0
  $oldEA = $ErrorActionPreference; $ErrorActionPreference = 'Stop'
  try {
    if ($PSBoundParameters.ContainsKey('ArgList') -and $null -ne $ArgList) { & $cmd @ArgList 2>&1 | Out-Null }
    else { & $cmd 2>&1 | Out-Null }
    return $LASTEXITCODE
  }
  catch { return -1 }
  finally { $ErrorActionPreference = $oldEA }
}
# one download helper for every call site. three tries, a pause between them,
# and BITS takes over for big files when the service is alive (it retries on
# its own and survives rough links). $MinBytes guards the "0 byte success".
function Test-DownloadComplete($file, $minBytes, $expectedBytes) {
  if (-not (Test-Path $file)) { return $false }
  try {
    $len = (Get-Item $file).Length
    if ($minBytes -gt 0 -and $len -lt $minBytes) { return $false }
    if ($expectedBytes -gt 0 -and $len -ne $expectedBytes) { return $false }
    return $true
  } catch { return $false }
}
function Invoke-Download {
  param(
    [string]$Url,
    [string]$OutFile,
    [int]$TimeoutSec = 600,
    [long]$MinBytes = 1MB,
    [long]$ExpectedBytes = 0,
    [switch]$Force
  )
  if (-not $Url -or -not $OutFile) { return $false }
  if (-not $Force -and (Test-DownloadComplete $OutFile $MinBytes $ExpectedBytes)) { return $true }
  $oldProg = $ProgressPreference; $ProgressPreference = 'SilentlyContinue'
  try {
    for ($i = 1; $i -le 3; $i++) {
      Write-Progress -Activity 'downloading' -Status "$(Split-Path $OutFile -Leaf) (attempt $i/3)" -PercentComplete -1 -EA SilentlyContinue
      # a partial from a killed run confuses everything, toss it first
      try { if (Test-Path $OutFile) { Remove-Item $OutFile -Force -EA SilentlyContinue } } catch {}
      try {
        $bitsSvc = Get-Service BITS -EA SilentlyContinue
        if (($MinBytes -ge 20MB -or $ExpectedBytes -ge 20MB) -and $bitsSvc -and $bitsSvc.StartType -ne 'Disabled') {
          try { Start-BitsTransfer -Source $Url -Destination $OutFile -TransferType Download -EA Stop }
          catch {
            # bits breaks on some boxes (policies, dead queues). plain http does not care.
            Log "  BITS failed ($($_.Exception.Message)), plain download instead."
            Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -TimeoutSec $TimeoutSec -EA Stop
          }
        } else {
          Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -TimeoutSec $TimeoutSec -EA Stop
        }
      } catch {
        Log "  WARN download attempt $i failed: $($_.Exception.Message)"
        if ($i -lt 3) { Start-Sleep -Seconds (2 * $i) }
        continue
      }
      if (Test-DownloadComplete $OutFile $MinBytes $ExpectedBytes) { return $true }
      Log "  WARN download attempt $i left a bad file, retrying."
      if ($i -lt 3) { Start-Sleep -Seconds (2 * $i) }
    }
    return $false
  } finally {
    Write-Progress -Activity 'downloading' -Completed -EA SilentlyContinue
    $ProgressPreference = $oldProg
  }
}
function Test-Admin {
  ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
# the quickcss the first installs shipped. untouched (or empty) upgrades to the
# real theme; anything else counts as someone's edits and is kept.
function Test-QuickcssStale($Text) {
  $bare = (("$Text" -replace '\uFEFF', '') -replace '\s', '')
  if (-not $bare) { return $true }
  return ($bare -eq '/*QuickCSSplaceholder.StockVesktoplook.Addyourownrulesbelowifyouwantthem.*/')
}
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
      $theme = Get-PropValue $vsJson 'workbench.colorTheme' ''
      if ($theme -eq 'Darkmatter') { Log '  ok: vscodium darkmatter theme' }
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
  if ($transcriptOn) { try { Stop-Transcript | Out-Null } catch {} }
  exit $(if ($miss) { 1 } else { 0 })
}

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

# ---------- 1. helpers ----------
# strict-mode safe: Get-Command returns $null when missing, and
# $null.Source throws under Set-StrictMode. use this everywhere.
function Get-CmdPath($name) {
  $c = Get-Command $name -EA SilentlyContinue
  if ($c) { return $c.Source } else { return $null }
}
# ---------- 2. winget. tiny10 has no store so this is always missing at first. ----------
function Test-WingetRuns {
  # staged on disk != runnable. gutted appx leaves a dead exe behind.
  if (-not (Get-Command winget -EA SilentlyContinue)) { return $false }
  return ((Invoke-Native { winget --version }) -eq 0)
}
function Ensure-Winget {
  if (Test-WingetRuns) { Log 'winget: found.'; return $true }
  # store-licensed package already staged but exe not on PATH yet. happens after a half-done bootstrap.
  try {
    if (Get-AppxPackage -Name 'Microsoft.DesktopAppInstaller' -EA SilentlyContinue) {
      $env:Path += ';' + (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps')
      if (Test-WingetRuns) { Log 'winget: found (staged package, PATH fixed).'; return $true }
    }
  } catch {}
  if ($NoWingetBootstrap) { Log 'winget: missing, bootstrap skipped (-NoWingetBootstrap).'; return $false }
  if (-not $online) { Log 'winget: offline, bootstrap skipped. connect or stage -OfflineDir.'; return $false }
  Log 'winget: missing (normal here). Bootstrapping...'
  $tmp = Join-Path $env:TEMP 'winget-bootstrap'; New-Item -ItemType Directory -Force -Path $tmp | Out-Null
  # appxsvc/clipsvc gutted or disabled on tiny10 = Add-AppxPackage hangs forever. try to wake them.
  # stripped AppX on purpose = winget impossible. bail fast, OfflineDir path below covers apps.
  if (-not (Get-Service AppXSvc -EA SilentlyContinue)) {
    Log 'winget: impossible here (AppXSvc stripped). use -NoWingetBootstrap -OfflineDir <path>.'
    return $false
  }
  foreach ($svc in @('AppXSvc','ClipSVC')) {
    try {
      $s = Get-Service $svc -EA SilentlyContinue
      if ($s -and $s.Status -ne 'Running') { Set-Service $svc -StartupType Manual -EA SilentlyContinue; Start-Service $svc -EA SilentlyContinue }
    } catch {}
  }
  # PS 5.1 renders a progress bar per byte on Invoke-WebRequest. 10x slower + looks stuck. off during bootstrap.
  $oldProg = $ProgressPreference; $ProgressPreference = 'SilentlyContinue'
  try {
    # skip what is already staged. reinstalling a newer-present appx is what hangs
    # on "Deployment operation progress ... Processing" for minutes.
    $deps = @(
      @{ name='VCLibs.x64.14.00.Desktop.appx'; url='https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx'; pkg='Microsoft.VCLibs.140.00.UWPDesktop' },
      @{ name='XAML.x64.appx'; url='https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.x64.appx'; pkg='Microsoft.UI.Xaml.2.8' }
    )
    foreach ($d in $deps) {
      try {
        if (Get-AppxPackage -Name $d.pkg -EA SilentlyContinue) { Log "dep already present, skip: $($d.pkg)"; continue }
      } catch {}
      $p = Join-Path $tmp $d.name
      # last hung run leaves a 12MB partial. a corrupt appx just hangs Add-AppxPackage again, so toss small files.
      try { if ((Test-Path $p) -and ((Get-Item $p).Length -lt 1MB)) { Remove-Item $p -Force -EA SilentlyContinue; Log "  tossed partial: $($d.name)" } } catch {}
      $off = if ($OfflineDir) { Join-Path $OfflineDir $d.name } else { '' }
      if ($off -and (Test-Path $off)) { Copy-Item $off $p -Force; Log "dep (offline): $($d.name)" }
      elseif (-not (Test-Path $p)) {
        # one dead download must not nuke the whole bootstrap
        Log "downloading $($d.name) (slow link, wait)..."
        if (Invoke-Download -Url $d.url -OutFile $p -TimeoutSec 300) { Log "  got $($d.name) ($([math]::Round((Get-Item $p).Length/1MB,1)) MB)" }
        else { Log "WARN download $($d.name) failed after 3 tries"; continue }
      } else { Log "dep cached, using: $($d.name) ($([math]::Round((Get-Item $p).Length/1MB,1)) MB)" }
      try { Log "installing $($d.name) (1-3 min on hdd, wait)..."; Add-AppxPackage -Path $p -EA Stop; Log "installed: $($d.name)" }
      catch {
        # 0x80073D06 = newer version already in the image. that's fine, move on.
        if ("$_" -match '0x80073D06|higher version|already installed') { Log "dep already newer, ok: $($d.name)" }
        else { Log "WARN dep $($d.name): $_" }
      }
    }
    # winget 1.24+ needs WindowsAppRuntime 1.x or the msixbundle dies with 0x80073CF3.
    try {
      $warDone = $null -ne (Get-AppxPackage -Name 'Microsoft.WindowsAppRuntime.1.8' -EA SilentlyContinue)
      if (-not $warDone) {
        $warOff = $null
        if ($OfflineDir -and (Test-Path $OfflineDir)) {
          $warOff = Get-ChildItem $OfflineDir -Recurse -Include '*AppRuntime*','*appruntime*' -EA SilentlyContinue |
            Where-Object { $_.Extension -in @('.msix','.appx','.exe') } | Select-Object -First 1
        }
        if ($warOff -and $warOff.Extension -ne '.exe') {
          Add-AppxPackage -Path $warOff.FullName -EA Stop; Log "installed (offline): $($warOff.Name)"
        } elseif ($warOff) {
          $proc = Start-Process $warOff.FullName -ArgumentList '--quiet' -Wait -PassThru -EA Stop
          if ($proc.ExitCode -eq 0) { Log "installed (offline): $($warOff.Name)" }
          else { Log "WARN WindowsAppRuntime offline exit=$($proc.ExitCode)" }
        } else {
          $warExe = Join-Path $tmp 'windowsappruntimeinstall-x64.exe'
          try { if ((Test-Path $warExe) -and ((Get-Item $warExe).Length -lt 1MB)) { Remove-Item $warExe -Force -EA SilentlyContinue } } catch {}
          if (-not (Test-Path $warExe)) {
            Log 'downloading WindowsAppRuntime 1.8 (~80MB, slow link, wait)...'
            if (-not (Invoke-Download -Url 'https://aka.ms/windowsappsdk/1.8/latest/windowsappruntimeinstall-x64.exe' -OutFile $warExe)) { throw 'WindowsAppRuntime download failed after 3 tries' }
            Log "  got WindowsAppRuntime ($([math]::Round((Get-Item $warExe).Length/1MB,1)) MB)"
          } else { Log 'WindowsAppRuntime installer cached, using it.' }
          $proc = Start-Process $warExe -ArgumentList '--quiet' -Wait -PassThru -EA Stop
          if ($proc.ExitCode -eq 0) { Log 'installed: WindowsAppRuntime 1.8' }
          else { Log "WARN WindowsAppRuntime exit=$($proc.ExitCode) (winget may still fail with 0x80073CF3)" }
        }
      } else { Log 'dep already present, ok: WindowsAppRuntime 1.8' }
    } catch {
      if ("$_" -match '0x80073D06|already installed') { Log 'dep already newer, ok: WindowsAppRuntime' }
      else { Log "WARN WindowsAppRuntime: $_" }
    }
    $msix = Join-Path $tmp 'Microsoft.DesktopAppInstaller.msixbundle'
    $offMsix = if ($OfflineDir) { Get-ChildItem $OfflineDir -Recurse -Filter '*.msixbundle' -EA SilentlyContinue | Select-Object -First 1 } else { $null }
    if ($offMsix) { Copy-Item $offMsix.FullName $msix -Force; Log "winget (offline): $($offMsix.Name)" }
    else {
      Log 'resolving latest winget release...'
      $rel = Invoke-RestMethod -Uri 'https://api.github.com/repos/microsoft/winget-cli/releases/latest' -UseBasicParsing -TimeoutSec 60 -EA Stop
      $asset = $rel.assets | Where-Object { $_.name -like '*.msixbundle' -and $_.name -notlike '*symbol*' } | Sort-Object size | Select-Object -First 1
      if (-not $asset) { throw 'no msixbundle in latest release' }
      try {
        if ((Test-Path $msix) -and -not (Test-DownloadComplete $msix 1MB $asset.size)) { Remove-Item $msix -Force -EA SilentlyContinue; Log '  tossed bad partial: winget msixbundle' }
      } catch {}
      if (-not (Test-Path $msix)) {
        Log "downloading $($asset.name) ($([math]::Round($asset.size/1MB,1)) MB, wait)..."
        if (-not (Invoke-Download -Url $asset.browser_download_url -OutFile $msix -ExpectedBytes $asset.size)) { throw 'winget msixbundle download failed after 3 tries' }
        Log "  got winget ($([math]::Round((Get-Item $msix).Length/1MB,1)) MB)"
      } else { Log 'winget msixbundle cached, using it.' }
    }
    try { Log 'installing winget msixbundle (1-3 min, wait)...'; Add-AppxPackage -Path $msix -EA Stop }
    catch {
      if ("$_" -match '0x80073D06|already installed') { Log 'winget already newer, ok.' }
      else { throw }
    }
    $env:Path += ';' + (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps')
    if (Test-WingetRuns) { Log 'winget: installed.'; return $true }
    Log 'winget staged but will not execute here (AppX gutted). using choco/offline instead.'
    return $false
  } catch { Log "WARN winget bootstrap failed: $_. Install App Installer manually, then re-run."; return $false }
  finally { $ProgressPreference = $oldProg }
}
if (-not $ConfigsOnly) {
  if ($DryRun) {
    $hasWinget = Test-WingetRuns
    if (-not $hasWinget) { Log 'winget: missing (dry-run, bootstrap skipped).' }
  } else { $hasWinget = Ensure-Winget }
} else { $hasWinget = $false }

# ---------- 2a. choco. plain ps1 + exe/msi, no appx. this is the slick path on stripped images. ----------
function Ensure-Chocolatey {
  if (Get-Command choco -EA SilentlyContinue) { Log 'choco: found.'; return $true }
  if ($NoChocoBootstrap) { Log 'choco: missing, bootstrap skipped (-NoChocoBootstrap).'; return $false }
  if (-not $isAdmin) { Log 'choco: missing, needs admin to bootstrap. re-run as admin.'; return $false }
  if (-not $online) { Log 'choco: offline, bootstrap skipped. connect or stage -OfflineDir.'; return $false }
  Log 'choco: missing. Bootstrapping from community.chocolatey.org (needs net, 2-5 min)...'
  $oldProg = $ProgressPreference; $ProgressPreference = 'SilentlyContinue'
  try {
    # the fetch is the flaky part. two more shots before giving up.
    $body = $null
    for ($i = 1; $i -le 3 -and -not $body; $i++) {
      try {
        $body = (New-Object Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1')
        if (-not $body -or $body.Length -lt 1024) { throw 'install.ps1 looks truncated' }
      } catch {
        Log "  WARN choco bootstrap download attempt $i failed: $($_.Exception.Message)"
        $body = $null
        if ($i -lt 3) { Start-Sleep -Seconds (2 * $i) }
      }
    }
    if (-not $body) { throw 'could not fetch install.ps1 after 3 tries' }
    # same script, executed without Invoke-Expression. PSSA sleeps better, behavior identical.
    & ([scriptblock]::Create($body))
    Refresh-Path
    if (Get-Command choco -EA SilentlyContinue) { Log 'choco: installed.'; return $true }
    Log 'WARN choco bootstrap: installer ran but choco not on PATH.'; return $false
  } catch { Log "WARN choco bootstrap failed: $_. Install from chocolatey.org manually, then re-run."; return $false }
  finally { $ProgressPreference = $oldProg }
}
# winget id -> community package. all 11 verified live on community.chocolatey.org.
# a bad name fails safe: choco errors, id lands in the retry list.
# no choco package: helium, all vcredists, dotnet. vesktop, telegram, qbittorrent,
# obs, git, vscodium, opencode ride github.
# 'python' tracks latest 3.x (3.15 at last check) while the winget id says 3.12. close enough.
$chocoMap = @{
  'Git.Git' = 'git'
  'OpenJS.NodeJS.LTS' = 'nodejs-lts'
  'Python.Python.3.12' = 'python'
  '7zip.7zip' = '7zip'
  'VideoLAN.VLC' = 'vlc'
  'qBittorrent.qBittorrent' = 'qbittorrent'
  'OBSProject.OBSStudio' = 'obs-studio'
  'Telegram.TelegramDesktop' = 'telegram'
  'VSCodium.VSCodium' = 'vscodium'
  'WiresharkFoundation.Wireshark' = 'wireshark'
  'SST.opencode' = 'opencode'
}
if (-not $ConfigsOnly) {
  if ($DryRun) {
    $hasChoco = [bool](Get-Command choco -EA SilentlyContinue)
    if ($hasChoco) { Log 'choco: found.' } else { Log 'choco: missing (dry-run, bootstrap skipped).' }
  } else { $hasChoco = Ensure-Chocolatey }
} else { $hasChoco = $false }

# github-direct. no manager at all, straight off release pages. patterns verified
# against the live releases api. x64 only, this box is x64. helium has no assets
# on its releases page, so it stays staged-only. unauthenticated api = 60 calls/hr,
# this runs max 9 per pass. cached under TEMP so re-runs skip the download.
$gitMap = @{
  'Vencord.Vesktop'        = @{ repo='Vencord/Vesktop'; pattern='Vesktop-Setup-*.exe' }
  'Telegram.TelegramDesktop' = @{ repo='telegramdesktop/tdesktop'; pattern='td-setup-win-x64-*.exe' }
  'qBittorrent.qBittorrent'  = @{ repo='qbittorrent/qBittorrent'; pattern='qbittorrent_*_x64_setup.exe' }
  'OBSProject.OBSStudio'   = @{ repo='obsproject/obs-studio'; pattern='OBS-Studio-*-Windows-x64-Installer.exe' }
  'Git.Git'                = @{ repo='git-for-windows/git'; pattern='Git-*-64-bit.exe' }
  'VSCodium.VSCodium'      = @{ repo='VSCodium/vscodium'; pattern='VSCodiumSetup-x64-*.exe' }
  'SST.opencode'           = @{ repo='sst/opencode'; pattern='opencode-windows-x64.zip' }
}
function Install-GitHubAsset($id) {
  $g = $gitMap[$id]
  $oldProg = $ProgressPreference; $ProgressPreference = 'SilentlyContinue'
  try {
    $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$($g.repo)/releases/latest" -UseBasicParsing -TimeoutSec 60 -EA Stop
    $asset = $rel.assets | Where-Object {
      $_.name -like $g.pattern -and $_.name -notmatch '\.(blockmap|yml|asc|txt|sha1|sha256)$' -and $_.name -notmatch 'arm64|aarch64'
    } | Select-Object -First 1
    if (-not $asset) { throw "no asset matching $($g.pattern)" }
    $dir = Join-Path (Join-Path $env:TEMP 'github-dl') ($id -replace '[^A-Za-z0-9]+','_')
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $dst = Join-Path $dir $asset.name
    # api knows the real size. a sleep-killed download leaves a big partial
    # that the old 1MB check waved through, then the installer choked on it.
    try {
      if (Test-Path $dst) {
        $len = (Get-Item $dst).Length
        if (($len -lt 1MB) -or ($asset.size -gt 0 -and $len -ne $asset.size)) { Remove-Item $dst -Force -EA SilentlyContinue; Log "  tossed bad partial: $($asset.name)" }
      }
    } catch {}
    if (-not (Test-Path $dst)) {
      Log "  downloading $($asset.name) ($([math]::Round($asset.size/1MB,1)) MB)..."
      if (-not (Invoke-Download -Url $asset.browser_download_url -OutFile $dst -ExpectedBytes $asset.size)) { throw "download failed after 3 tries: $($asset.name)" }
    } else { Log "  cached: $($asset.name)" }
    if (-not (Test-DownloadHash (Get-Item $dst))) {
      Log '  hash mismatch, retrying once...'
      if (-not (Invoke-Download -Url $asset.browser_download_url -OutFile $dst -ExpectedBytes $asset.size -Force)) { throw "download failed after 3 tries: $($asset.name)" }
      if (-not (Test-DownloadHash (Get-Item $dst))) { throw "hash still bad for $($asset.name)" }
    }
    Install-OfflineFile (Get-Item $dst)
  } finally { $ProgressPreference = $oldProg }
}
# evergreen vendor urls, HEAD-verified. no api, no manager. runtimes only:
# everything else desktop-ish has no stable direct link (versioned paths).
$directMap = @{
  'Microsoft.VCRedist.2015+.x86' = 'https://aka.ms/vs/17/release/vc_redist.x86.exe'
  'Microsoft.VCRedist.2015+.x64' = 'https://aka.ms/vs/17/release/vc_redist.x64.exe'
  'Microsoft.DotNet.DesktopRuntime.8' = 'https://aka.ms/dotnet/8.0/windowsdesktop-runtime-win-x64.exe'
}
function Install-DirectUrl($id) {
  $url = $directMap[$id]
  $oldProg = $ProgressPreference; $ProgressPreference = 'SilentlyContinue'
  try {
    $dir = Join-Path (Join-Path $env:TEMP 'direct-dl') ($id -replace '[^A-Za-z0-9]+','_')
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $dst = Join-Path $dir ($url -split '/')[-1]
    try { if ((Test-Path $dst) -and ((Get-Item $dst).Length -lt 1MB)) { Remove-Item $dst -Force -EA SilentlyContinue } } catch {}
    if (-not (Test-Path $dst)) {
      Log "  downloading $(Split-Path $url -Leaf)..."
      if (-not (Invoke-Download -Url $url -OutFile $dst)) { throw "download failed after 3 tries: $(Split-Path $url -Leaf)" }
    } else { Log "  cached: $(Split-Path $dst -Leaf)" }
    if (-not (Test-DownloadHash (Get-Item $dst))) {
      Log '  hash mismatch, retrying once...'
      if (-not (Invoke-Download -Url $url -OutFile $dst -Force)) { throw "download failed after 3 tries: $(Split-Path $url -Leaf)" }
      if (-not (Test-DownloadHash (Get-Item $dst))) { throw "hash still bad for $(Split-Path $dst -Leaf)" }
    }
    try { Install-OfflineFile (Get-Item $dst) }
    catch {
      # 1638 = that version already on disk. for runtimes that means covered.
      if ("$_" -match '1638') { Log '  already present, ok.' }
      else { throw }
    }
  } finally { $ProgressPreference = $oldProg }
}

# ---------- 2b. runtimes first. apps below need them. ----------
# ancient vendor tools still link the old redists, so all of them go on.
$runtimeApps = @(
  'Microsoft.VCRedist.2005.x86','Microsoft.VCRedist.2005.x64',
  'Microsoft.VCRedist.2008.x86','Microsoft.VCRedist.2008.x64',
  'Microsoft.VCRedist.2010.x86','Microsoft.VCRedist.2010.x64',
  'Microsoft.VCRedist.2012.x86','Microsoft.VCRedist.2012.x64',
  'Microsoft.VCRedist.2013.x86','Microsoft.VCRedist.2013.x64',
  'Microsoft.VCRedist.2015+.x86','Microsoft.VCRedist.2015+.x64',
  'Microsoft.DotNet.DesktopRuntime.8'
)
# 3.5 + DirectPlay for old vendor tools. some LTSC trims need install media, hence the warn.
if (-not $ConfigsOnly) {
  if ($DryRun) {
    Log '  [dry-run] would enable NetFx3 + DirectPlay via DISM.'
  } elseif ($isAdmin) {
    Start-Phase 'features'
    # install media carries its own payload. same-version sources only, per ms docs.
    $sxs = Get-PSDrive -PSProvider FileSystem -EA SilentlyContinue |
      ForEach-Object { Join-Path $_.Root 'sources\sxs' } |
      Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($sxs) { Log "  features source: $sxs" }
    $featFailed = 0
    foreach ($f in @('NetFx3','DirectPlay')) {
      # NOTE learned the hard way: native exes don't throw. check the exit code or the log lies.
      if ($sxs) { $exit = Invoke-Native { DISM /Online /Enable-Feature /FeatureName:$f /All /NoRestart /LimitAccess "/Source:$sxs" | Out-Null } }
      else { $exit = Invoke-Native { DISM /Online /Enable-Feature /FeatureName:$f /All /NoRestart | Out-Null } }
      # 3010 = success, reboot pending. not a failure.
      if ($exit -in @(0,3010)) { Log "${f}: enabled.$(if ($exit -eq 3010) { ' (reboot pending, normal)' })" }
      else { Log "WARN ${f}: DISM exit=$exit (insert install media so sources\sxs is visible) - enable manually for old vendor tools."; $featFailed++ }
    }
    Stop-Phase
    # a failed feature stays open so -Idempotent runs retry it next pass.
    if ($featFailed -eq 0) { Complete-Phase 'features' }
    else { Log "  features left open ($featFailed failed, no install media?) - re-run to retry." }
  } else { Log 'WARN NetFx3/DirectPlay: skipped (not admin).' }
}
# 4.8 is already in the image. moving on.
$coreApps = @(
  'ImputNet.Helium',
  'VSCodium.VSCodium',
  'Vencord.Vesktop',
  'Telegram.TelegramDesktop',
  'qBittorrent.qBittorrent',
  'VideoLAN.VLC',
  'OBSProject.OBSStudio',
  # automation basics
  'Git.Git',
  'OpenJS.NodeJS.LTS',
  'Python.Python.3.12',
  '7zip.7zip',
  'WiresharkFoundation.Wireshark',
  # me. terminal agent, reads .m files like anything else.
  'SST.opencode'
)
# shell pack (taste port from the linux box): small native cli tools, no wsl.
# winget covers them, or -OfflineDir stages the files like any other app.
$shellApps = @(
  'Starship.Starship',
  'ajeetdsouza.zoxide',
  'junegunn.fzf',
  'sharkdp.bat',
  'eza-community.eza',
  'Fastfetch-cli.Fastfetch'
)
$coreApps += $shellApps
$optionalApps = @('Obsidian.Obsidian','Spotify.Spotify')
if ($IncludeOptional) { $coreApps += $optionalApps }
# terminal wants win10 1903+. on ltsc 2019 it would just fail every run.
$wtBuild = 0
$wtOk = (-not $osInfo) -or (-not [int]::TryParse([string]$osInfo.Build, [ref]$wtBuild)) -or ($wtBuild -ge 18362)
if ($wtOk) { $coreApps += 'Microsoft.WindowsTerminal' }
else { Log 'terminal skipped (build too old for it).' }

# -Only/-SkipApps: substring match against app ids. runtimes can be filtered
# too, but that is on you, some apps need them.
function Test-AppFilter($id, $patterns) {
  foreach ($p in $patterns) { if ($id -like "*$p*") { return $true } }
  return $false
}
$appsAll = @($runtimeApps + $coreApps)
if ($Only.Count) {
  $appsAll = @($appsAll | Where-Object { Test-AppFilter $_ $Only })
  if (-not $appsAll.Count) { Log 'WARN: -Only matched no app ids. check the patterns.' }
  else { Log ('only: ' + ($appsAll -join ', ')) }
}
if ($SkipApps.Count) {
  $dropped = @($appsAll | Where-Object { Test-AppFilter $_ $SkipApps })
  if (@($dropped | Where-Object { $_ -like 'Microsoft.*' }).Count) { Log 'WARN: -SkipApps filtered runtimes. apps that need them may fail.' }
  if ($dropped.Count) { Log ('skipping on request: ' + ($dropped -join ', ')) }
  $appsAll = @($appsAll | Where-Object { -not (Test-AppFilter $_ $SkipApps) })
}

$failed = @()
$installed = @()
# apps we actually tried an engine on this run. skip-only failures don't need a retry pass.
$script:appAttempted = @{}
# per-app state so -Idempotent re-runs skip what already landed and retry
# only what failed. one small json next to phases.json.
function Get-AppState {
  $af = Join-Path $StateDir 'apps.json'
  if (-not (Test-Path $af)) { return @{} }
  try {
    $o = Get-Content $af -Raw | ConvertFrom-Json
    $d = @{}
    foreach ($p in $o.PSObject.Properties) { $d[$p.Name] = $p.Value }
    return $d
  } catch { return @{} }
}
function Test-AppDone($id) {
  if ($Force) { return $false }
  $st = Get-AppState
  return ($st.ContainsKey($id))
}
function Set-AppDone($id) {
  if ($DryRun) { return }
  try {
    if (-not (Test-Path $StateDir)) { New-Item -ItemType Directory -Force -Path $StateDir -EA Stop | Out-Null }
    $st = Get-AppState
    $st[$id] = (Get-Date).ToString('o')
    ($st | ConvertTo-Json) | Set-Content -Path (Join-Path $StateDir 'apps.json') -Encoding UTF8 -EA Stop
  } catch { Log "  WARN app state $id`: $_" }
}
function Find-OfflineInstaller($id) {
  if (-not $OfflineDir -or -not (Test-Path $OfflineDir)) { return $null }
  # exact match: per-ID subfolder under -OfflineDir. also sidesteps VC_redist name collisions.
  $sub = Join-Path $OfflineDir ($id -replace '[^A-Za-z0-9]+','_')
  if (Test-Path $sub) {
    return Get-ChildItem $sub -File -EA SilentlyContinue |
      Where-Object { $_.Extension -in @('.exe','.msi','.msix','.msixbundle','.appx','.zip') } |
      Sort-Object LastWriteTime -Descending | Select-Object -First 1
  }
  # sloppy fallback for hand-dropped folders. VCRedist needs the year check
  # because the last segment is just x64/x86 and matches literally everything.
  $segs = $id -split '\.'
  $cands = Get-ChildItem $OfflineDir -File -EA SilentlyContinue |
    Where-Object { $_.Name -like "*$($segs[-1])*" -and $_.Extension -in @('.exe','.msi','.msix','.msixbundle','.appx','.zip') }
  if ($segs[0] -eq 'Microsoft' -and $segs[1] -like 'VCRedist*') {
    $year = $segs[-2]
    $dated = $cands | Where-Object { $_.Name -like "*$year*" }
    if ($dated) { return $dated | Sort-Object LastWriteTime -Descending | Select-Object -First 1 }
    $redist = $cands | Where-Object { $_.Name -like '*redist*' }
    if ($redist) { Log "  WARN $id : year unverifiable in flat folder, using $(($redist | Select-Object -First 1).Name)" }
    return $redist | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  }
  return $cands | Sort-Object LastWriteTime -Descending | Select-Object -First 1
}
# silent flags per installer type. winget bakes the type into the filename
# (<name>_<ver>_<scope>_<arch>_<tech>_<lang>.<ext>) so read that, don't guess.
function Install-OfflineFile($file) {
  $seg = ($file.BaseName -split '[-_]')[0]
  switch ($file.Extension) {
    '.msi' {
      $proc = Start-Process msiexec -ArgumentList '/i', "`"$($file.FullName)`"", '/qn', '/norestart' -Wait -PassThru -EA Stop
      if ($proc.ExitCode -notin @(0,1641,3010)) { throw "msiexec exit=$($proc.ExitCode)" }
    }
    { $_ -in @('.appx','.msix','.msixbundle') } { Add-AppxPackage -Path $file.FullName -EA Stop }
    '.zip' {
      $dest = Join-Path $env:LOCALAPPDATA "Programs\$seg"
      New-Item -ItemType Directory -Force -Path $dest | Out-Null
      Expand-Archive -Path $file.FullName -DestinationPath $dest -Force -EA Stop
      # binary may sit in a subfolder (e.g. portable zips) - put the real dir on PATH
      $bin = Get-ChildItem $dest -Filter "$seg.exe" -Recurse -EA SilentlyContinue | Select-Object -First 1
      $bindir = if ($bin) { $bin.DirectoryName } else { $dest }
      $upath = [System.Environment]::GetEnvironmentVariable('Path','User')
      if ($upath -notlike "*$bindir*") {
        [System.Environment]::SetEnvironmentVariable('Path', "$upath;$bindir", 'User')
        $env:Path += ";$bindir"
      }
    }
    default {
      $exe = $file.FullName
      if ($file.Name -like '*_burn_*') {
        $proc = Start-Process $exe -ArgumentList '/install', '/quiet', '/norestart' -Wait -PassThru -EA Stop
      } elseif ($file.Name -like '*redist*' -or $file.Name -like '*dotnet*' -or $file.Name -like '*runtime*') {
        $proc = Start-Process $exe -ArgumentList '/q' -Wait -PassThru -EA Stop
      } elseif ($file.Name -like '*python*') {
        $proc = Start-Process $exe -ArgumentList '/quiet', 'InstallAllUsers=0', 'PrependPath=1' -Wait -PassThru -EA Stop
      } elseif ($file.Name -like '*VSCodium*' -or $file.Name -like '*Git*' -or $file.Name -like '*Telegram*' -or $file.Name -like '*tsetup*' -or $file.Name -like '*td-setup*') {
        $proc = Start-Process $exe -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART' -Wait -PassThru -EA Stop
      } else {
        $proc = Start-Process $exe -ArgumentList '/S' -Wait -PassThru -EA Stop
      }
      if ($proc.ExitCode -notin @(0,1641,3010)) { throw "installer exit=$($proc.ExitCode) ($($file.Name))" }
    }
  }
}
function Install-App($id) {
  # one app through the engines, in order. true when something landed.
  $off = Find-OfflineInstaller $id
  if ($off -and $Unattended) {
    # staged beats everything. no net needed, no manager needed.
    $script:appAttempted[$id] = $true
    Log "offline install: $($off.Name) for $id"
    try { Install-OfflineFile $off; Log '  ok (offline)'; return $true }
    catch { Log "  WARN offline failed, falling through: $_" }
  }
  if ($hasWinget -and $online) {
    $script:appAttempted[$id] = $true
    Log "winget install: $id"
    $exit = Invoke-Native { winget install --id $id -e --silent --accept-source-agreements --accept-package-agreements }
    if ($exit -eq 0) { Log '  ok'; return $true }
    Log "  WARN exit=$exit, falling through"
  }
  if ($hasChoco -and $chocoMap.ContainsKey($id)) {
    # NOTE native exe, exit code is the truth. try/catch alone lies.
    $script:appAttempted[$id] = $true
    Log "choco install: $($chocoMap[$id]) (for $id)"
    $exit = Invoke-Native { choco install $chocoMap[$id] -y --no-progress }
    if ($exit -eq 0) { Log '  ok'; return $true }
    Log "  WARN exit=$exit, falling through"
  }
  if ($online -and $gitMap.ContainsKey($id)) {
    $script:appAttempted[$id] = $true
    Log "github release: $id"
    try { Install-GitHubAsset $id; Log '  ok (github)'; return $true }
    catch { Log "  WARN github ${id}: $_"; return $false }
  }
  if ($online -and $directMap.ContainsKey($id)) {
    $script:appAttempted[$id] = $true
    Log "direct download: $id"
    try { Install-DirectUrl $id; Log '  ok (direct)'; return $true }
    catch { Log "  WARN direct ${id}: $_"; return $false }
  }
  if ($off) {
    Log "  SKIP $id (staged but no -Unattended. re-run with -Unattended or run $($off.Name) by hand)"
  } elseif (-not $chocoMap.ContainsKey($id) -and -not $gitMap.ContainsKey($id) -and -not $directMap.ContainsKey($id)) {
    Log "  SKIP $id (no choco/github source. stage it in -OfflineDir on a normal pc)"
  }
  return $false
}
if ((-not $ConfigsOnly) -and (Should-Run 'apps') -and ($DryRun -or $hasWinget -or $hasChoco -or ($OfflineDir -and (Test-Path $OfflineDir)))) {
  Start-Phase 'apps'
  $appTotal = $appsAll.Count
  $appIdx = 0
  foreach ($id in $appsAll) {
    $appIdx++
    if ($DryRun) { Log "  [dry-run] would install: $id"; continue }
    if ($Idempotent -and (Test-AppDone $id)) { Log "  skip (done): $id"; continue }
    Write-Progress -Activity 'installing apps' -Status "$appIdx/$appTotal $id" -PercentComplete ([int]((($appIdx - 1) * 100) / [math]::Max(1, $appTotal))) -EA SilentlyContinue
    if (Install-App $id) { $installed += $id; Set-AppDone $id }
    else { $failed += $id }
  }
  Write-Progress -Activity 'installing apps' -Completed -EA SilentlyContinue
  # one free retry pass. flaky links and rate limits are the usual causes.
  # skip-only failures never hit an engine, retrying them just re-logs the skip.
  if ($failed.Count -and $online) {
    $retryList = @($failed | Where-Object { $script:appAttempted.ContainsKey($_) })
    $skipOnly = @($failed | Where-Object { -not $script:appAttempted.ContainsKey($_) })
    if ($retryList.Count) {
      Log "retrying $($retryList.Count) failed app(s)..."
      $failed = @($skipOnly)
      foreach ($id in $retryList) {
        Log "retry: $id"
        if (Install-App $id) { $installed += $id; Set-AppDone $id }
        else { $failed += $id }
      }
    }
  }
  if ($Only.Count) { Log 'bulk upgrades skipped (selective -Only run).' }
  elseif ($DryRun) { Log '[dry-run] would upgrade packages (winget upgrade --all / choco upgrade all).' }
  else {
    if ($hasWinget -and $online) {
      $exit = Invoke-Native { winget upgrade --all --silent --accept-source-agreements --accept-package-agreements }
      if ($exit -eq 0) { Log '  winget upgrade done.' } else { Log "  WARN winget upgrade exit=$exit" }
    }
    elseif ($hasWinget) { Log 'SKIP winget upgrade (offline).' }
    if ($hasChoco -and $online) {
      $exit = Invoke-Native { choco upgrade all -y --no-progress }
      if ($exit -eq 0) { Log '  choco upgrade done.' } else { Log "  WARN choco upgrade exit=$exit" }
    }
    elseif ($hasChoco) { Log 'SKIP choco upgrade (offline).' }
  }
  Stop-Phase
  # failures keep the phase open so -Idempotent re-runs retry them. an empty
  # list (typo in -Only, everything -SkipApps'd) stays open too, on purpose.
  if ($failed.Count -eq 0 -and $appsAll.Count -gt 0) { Complete-Phase 'apps' }
  elseif ($appsAll.Count -eq 0) { Log '  nothing selected, apps phase left open.' }
  else { Log "  apps left open ($($failed.Count) failed) - re-run to retry." }
} elseif ($ConfigsOnly) { Log 'Configs-only: apps skipped.' } else {
  Log 'SKIP installs (no winget, no choco, no -OfflineDir). Get net for choco, or stage files in -OfflineDir - nothing marked failed yet.'
}

# fresh installs don't land on PATH in this session. re-read it or python/codium are "missing".
Refresh-Path
Log 'PATH refreshed.'

# bench drivers (ch340/cp210x/st-link). point at a folder of extracted vendor infs.
if ($DriverDir -and (Test-Path $DriverDir) -and (-not $ConfigsOnly)) {
  if ($DryRun) { Log "  [dry-run] would add drivers from $DriverDir." }
  elseif ($isAdmin) {
    Log "drivers: $DriverDir"
    $exit = Invoke-Native { pnputil /add-driver "$DriverDir\*.inf" /subdirs /install }
    if ($exit -in @(0,3010)) { Log "  drivers staged+installed$(if ($exit -eq 3010) { ' (reboot pending)' })" }
    else { Log "  WARN pnputil exit=$exit (check the inf folder, install manually)" }
  } else { Log '  WARN drivers: skipped (not admin).' }
} elseif ($DriverDir) { Log '  WARN drivers: folder missing or configs-only run.' }

Log 'NOTE manual-only: ExplorerBlurMica (Maplespe releases, optional), Spicetify (after Spotify: Invoke-WebRequest -UseBasicParsing https://raw.githubusercontent.com/spicetify/cli/main/install.ps1 | Invoke-Expression).'

# ---------- 3. configs ----------
if (Should-Run 'configs') {
Log 'Configs...'
Start-Phase 'configs'
function Copy-Config($src, $dst) {
  if (-not (Test-Path $src)) { Log "  SKIP missing in repo (not fatal): $src"; return }
  if ($DryRun) { Log "  [dry-run] would copy: $dst"; return }
  New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
  Copy-Item $src $dst -Force -EA Stop
  Log "  $dst"
}
# stock PS 5.1 profile lives under WindowsPowerShell in docs. that's just how it is.
$docPS = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1'
Copy-Config (Join-Path $Repo 'PowerShell\Microsoft.PowerShell_profile.ps1') $docPS
if (Get-Command pwsh -EA SilentlyContinue) {
  Copy-Config (Join-Path $Repo 'PowerShell\Microsoft.PowerShell_profile.ps1') (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell\Microsoft.PowerShell_profile.ps1')
}

# extensions live in extensions.txt next to the script. edit that file, not this one.
$codium = Get-CmdPath 'codium'
if (-not $codium) {
  foreach ($cand in @("$env:LOCALAPPDATA\Programs\VSCodium\VSCodium.exe",
                      "$env:ProgramFiles\VSCodium\VSCodium.exe",
                      "${env:ProgramFiles(x86)}\VSCodium\VSCodium.exe")) {
    if (Test-Path $cand) { $codium = $cand; break }
  }
}

# vscodium eats vscode settings as-is. extensions come from open vsx though.
# appdata dir only shows up after first launch, so seed it when the exe exists.
$vs = Join-Path $env:APPDATA 'VSCodium\User\settings.json'
if ((Test-Path (Split-Path $vs)) -or ($codium -and (Test-Path $codium))) {
  if (-not $DryRun) { New-Item -ItemType Directory -Force -Path (Split-Path $vs) | Out-Null }
  Copy-Config (Join-Path $Repo 'VSCodium\settings.json') $vs
  Copy-Config (Join-Path $Repo 'VSCodium\keybindings.json') (Join-Path $env:APPDATA 'VSCodium\User\keybindings.json')
  # darkmatter theme ships as a folder extension. the folder name has to carry
  # the version or vscodium pretends it is not installed.
  $themeDst = Join-Path $env:USERPROFILE '.vscode-oss\extensions\xfcemlg.darkmatter-theme-0.6.0'
  if ($DryRun) { Log "  [dry-run] would copy: $themeDst (plus drop any older versions)" }
  else {
    try {
      # a version bump would otherwise leave both folders there and vscodium gets grumpy.
      Get-ChildItem (Split-Path $themeDst -Parent) -Directory -Filter 'xfcemlg.darkmatter-theme-*' -EA SilentlyContinue |
        Where-Object { $_.Name -ne (Split-Path $themeDst -Leaf) } |
        ForEach-Object { Remove-Item $_.FullName -Recurse -Force -EA SilentlyContinue; Log "  dropped old theme folder: $($_.Name)" }
      New-Item -ItemType Directory -Force -Path $themeDst | Out-Null
      Copy-Item (Join-Path $Repo 'VSCodium\darkmatter-theme\*') $themeDst -Recurse -Force -EA Stop
      Log "  $themeDst"
    } catch { Log "  WARN vscodium theme: $_" }
  }
}
else { Log '  VSCodium not installed yet - settings kept in repo VSCodium/.' }
if ($DryRun -and (-not $ConfigsOnly)) {
  Log '  [dry-run] would install vscodium extensions from extensions.txt.'
} elseif ($codium -and (Test-Path $codium) -and (-not $ConfigsOnly)) {
  $extList = @('yasirarafat.opencode-ai-chat','Gimly81.matlab')
  $extFile = Join-Path $Repo 'VSCodium\extensions.txt'
  if (Test-Path $extFile) {
    $extList = @(Get-Content $extFile -EA SilentlyContinue |
      Where-Object { $_ -and $_ -notmatch '^\s*#' } |
      ForEach-Object { $_.Trim() } |
      Where-Object { $_ })
  }
  foreach ($ext in $extList) {
    try {
      $exit = Invoke-Native { & $codium --install-extension $ext }
      if ($exit -ne 0) { throw "exit=$exit" }
      Log "  vscodium ext: $ext"
    }
    catch { Log "  WARN vscodium ext ${ext}: install manually from Open VSX." }
  }
  Log '  NOTE: MATLAB extension (MathWorks) is MS-marketplace only - download the .vsix and: codium --install-extension <file>.vsix'
} elseif ($ConfigsOnly) { Log '  extensions skipped (configs-only).' } else { Log '  VSCodium exe not found - extensions skipped.' }

# pip libs for bench work. needs python on PATH, so this runs after the refresh above.
if (-not $ConfigsOnly) {
  if ($DryRun) { Log '  [dry-run] would pip install: numpy scipy matplotlib pyserial pymodbus' }
  else {
  try {
    $exit = Invoke-Native { python -m pip install --upgrade pip }
    if ($exit -ne 0) { throw "pip upgrade exit=$exit" }
    $exit = Invoke-Native { python -m pip install numpy scipy matplotlib pyserial pymodbus }
    if ($exit -ne 0) { throw "pip install exit=$exit" }
    Log '  python libs: numpy scipy matplotlib pyserial pymodbus'
  } catch { Log '  WARN pip libs skipped - run manually: python -m pip install numpy scipy matplotlib pyserial pymodbus' }
  }
} else { Log '  python libs skipped (configs-only).' }

# fresh installs get configs; -ConfigsOnly (or -Force) re-deploys over existing ones.
function Copy-Fresh($src, $dst) {
  if (($ConfigsOnly -or $Force) -or -not (Test-Path $dst)) { Copy-Config $src $dst }
  else { Log "  keep existing: $dst" }
}
Copy-Fresh (Join-Path $Repo 'Vesktop\settings.json') (Join-Path $env:APPDATA 'Vesktop\settings.json')
Copy-Fresh (Join-Path $Repo 'qBittorrent\qbittorrent.ini') (Join-Path $env:APPDATA 'qBittorrent\qbittorrent.ini')
Copy-Fresh (Join-Path $Repo 'VLC\vlcrc') (Join-Path $env:APPDATA 'vlc\vlcrc')
Copy-Fresh (Join-Path $Repo 'OBS\profiles\Recording\basic.ini') (Join-Path $env:APPDATA 'obs-studio\basic\profiles\Recording\basic.ini')
# git defaults. fresh-only on purpose: identity is blank in the repo copy, so an overwrite
# on re-run would wipe the name/email you set. (needs Copy-Fresh, so it lives down here.)
Copy-Fresh (Join-Path $Repo 'Git\.gitconfig') (Join-Path $env:USERPROFILE '.gitconfig')
# quickcss ships as a placeholder, so an untouched one upgrades to the real
# darkmatter theme on re-run. a quickcss you edited yourself is kept.
$qcss = Join-Path $env:APPDATA 'Vesktop\settings\quickcss.css'
$qsrc = Join-Path $Repo 'Vesktop\quickcss.css'
$qcur = $null
if (Test-Path $qcss) { $qcur = Get-Content $qcss -Raw -EA SilentlyContinue }
if ((Test-QuickcssStale $qcur) -or $ConfigsOnly -or $Force) { Copy-Config $qsrc $qcss } else { Log "  keep existing: $qcss" }
# opencode global config: curated MCP servers (context7, playwright). fresh-only.
Copy-Fresh (Join-Path $Repo 'config\opencode\opencode.json') (Join-Path $env:USERPROFILE '.config\opencode\opencode.json')
# opencode global rules and on-demand skills. fresh-only per file, so your own edits survive a re-run.
Copy-Fresh (Join-Path $Repo 'config\AGENTS.global.md') (Join-Path $env:USERPROFILE '.config\opencode\AGENTS.md')
$ocSkillSrc = Join-Path $Repo 'config\opencode-skills'
if (Test-Path $ocSkillSrc) {
  Get-ChildItem $ocSkillSrc -Recurse -File | ForEach-Object {
    $rel = $_.FullName.Substring($ocSkillSrc.Length).TrimStart('\', '/')
    Copy-Fresh $_.FullName (Join-Path $env:USERPROFILE ('.config\opencode\skills\' + $rel))
  }
}
# terminal config, fresh-only. only where terminal can actually land (same build gate as the install).
if ($wtOk) { Copy-Fresh (Join-Path $Repo 'WindowsTerminal\settings.json') (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json') }
$ocPlugins = Join-Path $env:USERPROFILE '.config\opencode\plugins'
if (-not $DryRun -and -not (Test-Path $ocPlugins)) { New-Item -ItemType Directory -Force -Path $ocPlugins | Out-Null }
if (Test-Path (Join-Path $Repo 'Helium\master_preferences')) {
  $heData = Join-Path $env:LOCALAPPDATA 'Helium\User Data'
  if (-not (Test-Path $heData)) { Copy-Config (Join-Path $Repo 'Helium\master_preferences') (Join-Path $heData 'master_preferences') }
  else { Log '  Helium already ran - master_preferences ignored (change settings in UI).' }
}

# drop your .ttfs in Fonts/ and they get installed. admin only, windows rules.
$fontDir = Join-Path $Repo 'Fonts'
if ((Test-Path $fontDir) -and $isAdmin) {
  if ($DryRun) { Log '  [dry-run] would install fonts from Fonts/.' }
  else {
  try {
    $shell = New-Object -ComObject Shell.Application -EA Stop
    $fFolder = $shell.Namespace(0x14)
    Get-ChildItem $fontDir -Include *.ttf,*.otf -Recurse -EA SilentlyContinue | ForEach-Object {
      try { $fFolder.CopyHere($_.FullName, 0x10); Log "  font: $($_.Name)" } catch { Log "  WARN font $($_.Name): $_" }
    }
  } catch { Log "  WARN fonts: shell object unavailable on this trim - right-click Install the .ttfs." }
  }
} else { Log '  Fonts: drop JetBrainsMono Nerd Font + Monocraft .ttf into Fonts/ and re-run as admin (or right-click Install).' }
Stop-Phase
Complete-Phase 'configs'
} else { Log 'Configs skipped (already done).' }


# ---------- 5. defaults and finish helper, stock panel untouched ----------
if ((-not $ConfigsOnly) -and (Should-Run 'autostart')) {
Log 'Autostart...'
Start-Phase 'autostart'
# helium default. per-user, needs no admin.
if ($DryRun) { Log '  [dry-run] would set Helium as default browser.' }
else {
try {
  $helium = Get-CmdPath 'helium'
  if (-not $helium) {
    foreach ($root in @("$env:LOCALAPPDATA\Helium", "$env:ProgramFiles\Helium", "${env:ProgramFiles(x86)}\Helium")) {
      if (-not (Test-Path $root)) { continue }
      $h = Get-ChildItem $root -Filter 'helium.exe' -Recurse -EA SilentlyContinue | Select-Object -First 1
      if ($h) { $helium = $h.FullName; break }
    }
  }
  if ($helium) { Start-Process $helium -ArgumentList '--make-default-browser' -WindowStyle Hidden -EA Stop; Log '  Helium default-browser requested (confirm in Settings > Apps > Default apps).' }
  else { Log '  Helium not found yet - set default manually in Settings > Apps > Default apps.' }
} catch { Log "  WARN default browser: $_" }
}

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
    @{ n='7zip'; cmd={ Get-Command 7z -EA Stop | Out-Null } }
  )) {
    if ((Invoke-Native $s.cmd) -eq 0) { Log "  smoke ok: $($s.n)" }
    else { Log "  smoke MISSING: $($s.n)" }
  }
  }
}

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
if ($DryRun) { Log 'Dry-run finished. nothing changed, nothing marked done.' }
elseif ($ConfigsOnly) { Log 'Configs-only done.' }
else {
Log 'NEXT:'
Log '  1. reboot, stock desktop as-is.'
Log '  2. double-click Desktop Win-Iot-Finish.cmd (opencode auth + optional password).'
Log '  3. MATLAB via campus license + USB-serial drivers (CH340/CP210x/ST-Link) manually.'
}
if ($Reboot -and -not $DryRun) {
  Log 'rebooting in 60s (-Reboot). save your stuff.'
  shutdown /r /t 60 /c 'Win-Iot setup done. rebooting.' 2>&1 | Out-Null
}
if ($Reboot -and $DryRun) { Log 'reboot skipped (dry-run).' }
if ($transcriptOn) { try { Stop-Transcript | Out-Null } catch {} }
