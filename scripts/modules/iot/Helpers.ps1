# IoT helper functions extracted from install-Win-Iot.ps1.
# Dot-sourced into the installer scope; relies on $DryRun, $Repo, $ConfigsOnly, $Force.

function Copy-Config($src, $dst) {
  if (-not (Test-Path $src)) { Log "  SKIP missing in repo (not fatal): $src"; return }
  if ($DryRun) { Log "  [dry-run] would copy: $dst"; return }
  New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
  Copy-Item $src $dst -Force -EA Stop
  Log "  $dst"
}

function New-IotShortcut {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Target,
    [string]$Arguments = ''
  )
  if ($DryRun) { Log "  [dry-run] would create shortcut: $Path"; return }
  $dir = Split-Path $Path
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $shell = New-Object -ComObject WScript.Shell
  $lnk = $shell.CreateShortcut($Path)
  $lnk.TargetPath = $Target
  $lnk.Arguments = $Arguments
  $lnk.IconLocation = $Target
  $lnk.Save()
  Log "  shortcut: $Path"
}

function Get-LibreWolfPathIot {
  $candidates = @(
    'C:\Program Files\LibreWolf\librewolf.exe',
    (Join-Path $env:LOCALAPPDATA 'LibreWolf\librewolf.exe'),
    (Get-CmdPath 'librewolf')
  )
  foreach ($candidate in $candidates) {
    if ($candidate -and (Test-Path $candidate)) { return $candidate }
  }
  return $null
}

function Set-LibreWolfProfilesIot {
  $lw = Get-LibreWolfPathIot
  if (-not $lw) { Log '  LibreWolf not found yet - profiles skipped.'; return }

  $dataRoot = Join-Path $env:APPDATA 'LibreWolf'
  $profilesRoot = Join-Path $dataRoot 'Profiles'
  $iniPath = Join-Path $dataRoot 'profiles.ini'
  $existing = ''
  if (Test-Path $iniPath) { $existing = Get-Content $iniPath -Raw }
  $shortcutFolder = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\LibreWolf Profiles'

  if (-not $DryRun -and -not (Test-Path $profilesRoot)) { New-Item -ItemType Directory -Force -Path $profilesRoot | Out-Null }

  foreach ($profile in @('personal', 'uni', 'social')) {
    $profilePath = Join-Path $profilesRoot $profile
    $known = $existing -match ('(?m)^Name=' + [regex]::Escape($profile) + '\r?$')
    if ($known -and (Test-Path $profilePath)) { Log "  profile exists: $profile"; continue }
    if ($DryRun) { Log "  [dry-run] would create LibreWolf profile $profile at $profilePath" }
    else {
      $code = Invoke-Native { & $lw '-CreateProfile' "$profile $profilePath" }
      if ($code -eq 0) { Log "  profile: $profile" } else { Log "  WARN profile ${profile}: exit $code" }
    }
    $shortcut = Join-Path $shortcutFolder "$profile.lnk"
    if (Test-Path $shortcut) { Log "  shortcut exists: $shortcut" }
    else { New-IotShortcut -Path $shortcut -Target $lw -Arguments "-P `"$profile`" -no-remote" }
  }
}

function Copy-Fresh($src, $dst) {
  if (($ConfigsOnly -or $Force) -or -not (Test-Path $dst)) { Copy-Config $src $dst }
  else { Log "  keep existing: $dst" }
}