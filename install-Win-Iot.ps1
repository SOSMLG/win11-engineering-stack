<#
.SYNOPSIS
  My Win10/Win11 IoT (Enterprise) LTSC setup. Unattended, rerunnable.
.DESCRIPTION
  Built for a tiny10 box with no store and usually no network
  on first boot. PS 5.1, stock Windows desktop, LibreWolf, VSCodium.
  No extra shell, no extra window manager. Stock colors everywhere.
  Engines per app, first hit wins: staged -OfflineDir files, winget,
  github releases, direct vendor URLs. Log lands in C:\Windows\Logs\Win-Iot-Setup
  either way.
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File install-Win-Iot.ps1
  powershell -ExecutionPolicy Bypass -File install-Win-Iot.ps1 -Unattended -OfflineDir D:\Offline
  powershell -ExecutionPolicy Bypass -File install-Win-Iot.ps1 -Unattended -DriverDir D:\Drivers -Reboot
  powershell -ExecutionPolicy Bypass -File install-Win-Iot.ps1 -Minimal -Unattended
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
  [switch]$Minimal,
  [switch]$Unattended,
  [switch]$NoWingetBootstrap,
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
# log, state, and transcript start after -Verify, so the read-only path writes nothing.
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

# ---------- 3. configs ----------
if (Should-Run 'configs') {
Log 'Configs...'
Start-Phase 'configs'
# Copy-Config provided by scripts/modules/iot/Helpers.ps1
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
  # graphite amber theme ships as a folder extension. the folder name has to carry
  # the version or vscodium pretends it is not installed.
  $themeDst = Join-Path $env:USERPROFILE '.vscode-oss\extensions\xfcemlg.graphite-amber-theme-0.6.0'
  if ($DryRun) { Log "  [dry-run] would copy: $themeDst (plus drop any older versions)" }
  else {
    try {
      # a version bump would otherwise leave both folders there and vscodium gets grumpy.
      Get-ChildItem (Split-Path $themeDst -Parent) -Directory -Filter 'xfcemlg.graphite-amber-theme-*' -EA SilentlyContinue |
        Where-Object { $_.Name -ne (Split-Path $themeDst -Leaf) } |
        ForEach-Object { Remove-Item $_.FullName -Recurse -Force -EA SilentlyContinue; Log "  dropped old theme folder: $($_.Name)" }
      New-Item -ItemType Directory -Force -Path $themeDst | Out-Null
      Copy-Item (Join-Path $Repo 'VSCodium\graphite-amber-theme\*') $themeDst -Recurse -Force -EA Stop
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

# New-IotShortcut provided by scripts/modules/iot/Helpers.ps1

# Get-LibreWolfPathIot provided by scripts/modules/iot/Helpers.ps1

# Set-LibreWolfProfilesIot provided by scripts/modules/iot/Helpers.ps1

# fresh installs get configs; -ConfigsOnly (or -Force) re-deploys over existing ones.
# Copy-Fresh provided by scripts/modules/iot/Helpers.ps1
Copy-Fresh (Join-Path $Repo 'Vesktop\settings.json') (Join-Path $env:APPDATA 'Vesktop\settings.json')
Copy-Fresh (Join-Path $Repo 'qBittorrent\qbittorrent.ini') (Join-Path $env:APPDATA 'qBittorrent\qbittorrent.ini')
Copy-Fresh (Join-Path $Repo 'VLC\vlcrc') (Join-Path $env:APPDATA 'vlc\vlcrc')
Copy-Fresh (Join-Path $Repo 'OBS\profiles\Recording\basic.ini') (Join-Path $env:APPDATA 'obs-studio\basic\profiles\Recording\basic.ini')
# git defaults. fresh-only on purpose: identity is blank in the repo copy, so an overwrite
# on re-run would wipe the name/email you set. (needs Copy-Fresh, so it lives down here.)
Copy-Fresh (Join-Path $Repo 'Git\.gitconfig') (Join-Path $env:USERPROFILE '.gitconfig')
# quickcss ships as a placeholder, so an untouched one upgrades to the real
# graphite amber theme on re-run. a quickcss you edited yourself is kept.
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
# librewolf: safe defaults plus three isolated profiles. fresh-only overrides.
Copy-Fresh (Join-Path $Repo 'LibreWolf\librewolf.overrides.cfg') (Join-Path $env:USERPROFILE '.librewolf\librewolf.overrides.cfg')
Set-LibreWolfProfilesIot
# mem reduct: repo ships a comment-only ini so the app has a stable config file.
Copy-Fresh (Join-Path $Repo 'MemReduct\memreduct.ini') (Join-Path $env:APPDATA 'Henry++\Mem Reduct\memreduct.ini')

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
