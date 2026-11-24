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
  # stripped AppX on purpose = winget impossible. bail fast, staged/direct paths below cover apps.
  if (-not (Get-Service AppXSvc -EA SilentlyContinue)) {
    Log 'winget: impossible here (AppXSvc stripped). staged files and direct sources still apply.'
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
    Log 'winget staged but will not execute here (AppX gutted). using staged files and direct sources instead.'
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

# ---------- 2a. github-direct. no package manager, straight off release pages. ----------
# patterns verified against the live releases api. x64 only, this box is x64.
# unauthenticated api = 60 calls/hr, this runs max 9 per pass. cached under TEMP
# so re-runs skip the download.
$gitMap = @{
  'Vencord.Vesktop'        = @{ repo='Vencord/Vesktop'; pattern='Vesktop-Setup-*.exe' }
  'Telegram.TelegramDesktop' = @{ repo='telegramdesktop/tdesktop'; pattern='td-setup-win-x64-*.exe' }
  'qBittorrent.qBittorrent'  = @{ repo='qbittorrent/qBittorrent'; pattern='qbittorrent_*_x64_setup.exe' }
  'OBSProject.OBSStudio'   = @{ repo='obsproject/obs-studio'; pattern='OBS-Studio-*-Windows-x64-Installer.exe' }
  'Git.Git'                = @{ repo='git-for-windows/git'; pattern='Git-*-64-bit.exe' }
  'VSCodium.VSCodium'      = @{ repo='VSCodium/vscodium'; pattern='VSCodiumSetup-x64-*.exe' }
  'SST.opencode'           = @{ repo='sst/opencode'; pattern='opencode-windows-x64.zip' }
  'Joplin.Joplin'          = @{ repo='laurent22/joplin'; pattern='Joplin-Setup-*.exe' }
  'KRTirtho.Spotube'       = @{ repo='KRTirtho/spotube'; pattern='Spotube-windows-x86_64-setup.exe' }
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
  'LibreWolf.LibreWolf',
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
$optionalApps = @('Joplin.Joplin','KRTirtho.Spotube','Henry++.MemReduct')
# Optional apps are part of the default install; -Minimal leaves them out.
if (-not $Minimal) { $coreApps += $optionalApps }
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
# apps with no usable engine on this image are skips, not failures.
$script:appSkipped = @{}
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
      } elseif ($file.Name -like '*VSCodium*' -or $file.Name -like '*Git*' -or $file.Name -like '*Telegram*' -or $file.Name -like '*tsetup*' -or $file.Name -like '*td-setup*' -or $file.Name -like '*Spotube*') {
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
    $script:appSkipped[$id] = $true
  } elseif (-not $gitMap.ContainsKey($id) -and -not $directMap.ContainsKey($id)) {
    Log "  SKIP $id (no github/direct fallback. stage it in -OfflineDir or retry with winget)"
    $script:appSkipped[$id] = $true
  }
  return $false
}
if ((-not $ConfigsOnly) -and (Should-Run 'apps') -and ($DryRun -or $online -or ($OfflineDir -and (Test-Path $OfflineDir)))) {
  Start-Phase 'apps'
  $appTotal = $appsAll.Count
  $appIdx = 0
  foreach ($id in $appsAll) {
    $appIdx++
    if ($DryRun) { Log "  [dry-run] would install: $id"; continue }
    if ($Idempotent -and (Test-AppDone $id)) { Log "  skip (done): $id"; continue }
    Write-Progress -Activity 'installing apps' -Status "$appIdx/$appTotal $id" -PercentComplete ([int]((($appIdx - 1) * 100) / [math]::Max(1, $appTotal))) -EA SilentlyContinue
    if (Install-App $id) { $installed += $id; Set-AppDone $id }
    elseif (-not $script:appSkipped.ContainsKey($id)) { $failed += $id }
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
  elseif ($DryRun) { Log '[dry-run] would upgrade packages (winget upgrade --all).' }
  elseif ($hasWinget -and $online) {
    $exit = Invoke-Native { winget upgrade --all --silent --accept-source-agreements --accept-package-agreements }
    if ($exit -eq 0) { Log '  winget upgrade done.' } else { Log "  WARN winget upgrade exit=$exit" }
  }
  elseif ($hasWinget) { Log 'SKIP winget upgrade (offline).' }
  Stop-Phase
  # failures keep the phase open so -Idempotent re-runs retry them. an empty
  # list (typo in -Only, everything -SkipApps'd) stays open too, on purpose.
  if ($failed.Count -eq 0 -and $appsAll.Count -gt 0) { Complete-Phase 'apps' }
  elseif ($appsAll.Count -eq 0) { Log '  nothing selected, apps phase left open.' }
  else { Log "  apps left open ($($failed.Count) failed) - re-run to retry." }
} elseif ($ConfigsOnly) { Log 'Configs-only: apps skipped.' } else {
  Log 'SKIP installs (no network, no winget, no -OfflineDir). Connect for winget/github/direct sources, or stage files in -OfflineDir - nothing marked failed yet.'
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

# Helpers.ps1 is dot-sourced separately by the installer.
