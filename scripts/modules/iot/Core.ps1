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
