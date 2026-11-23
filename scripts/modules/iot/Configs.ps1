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
