$script:MercuryGramVersion = '7.4.4.1'
$script:MercuryGramSha256 = 'BCE4A20B0389095CCD5DF95C24FC0F9CA23D4EAF758F259986AC579F548F1774'

function Install-AppPackage {
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$Command
    )

    if ($Command -and (Get-CommandPath $Command)) {
        Write-Skip "$Name is already available ($Command)."
        return
    }
    Install-WingetPackage -Id $Id -Name $Name
}

function Test-FontInstalled {
    param([string]$Pattern)
    $keys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts',
        'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
    )
    foreach ($key in $keys) {
        $properties = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
        if ($null -eq $properties) { continue }
        foreach ($property in $properties.PSObject.Properties) {
            if ($property.Name -match $Pattern) { return $true }
        }
    }
    return $false
}

function Install-MercuryGram {
    $version = $script:MercuryGramVersion
    $expected = $script:MercuryGramSha256
    $destination = Join-Path $env:LOCALAPPDATA "Programs\Mercurygram\$version"
    $exe = Join-Path $destination 'Mercurygram\Mercurygram.exe'

    if (Test-Path $exe) {
        Write-Skip "MercuryGram $version is already installed."
        return
    }

    $url = "https://github.com/Mercurygram/mdesktop/releases/download/v$version/Mercurygram-$version-windows-x86_64-portable.zip"
    Write-Detail "MercuryGram $version from GitHub releases."

    if ($script:DryRun) {
        Write-Detail "[dry-run] download $url"
        Write-Detail "[dry-run] verify SHA256 $expected"
        Write-Detail "[dry-run] extract to $destination"
        Write-Detail "[dry-run] create MercuryGram shortcuts"
        return
    }

    $tempRoot = Join-Path $env:TEMP ("mercurygram-{0}" -f (Get-Timestamp))
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    $zip = Join-Path $tempRoot 'mercurygram.zip'

    $previousProgress = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try {
        Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing -TimeoutSec 600
    }
    finally {
        $ProgressPreference = $previousProgress
    }

    $actual = (Get-FileHash -Path $zip -Algorithm SHA256).Hash
    if ($actual -ne $expected) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        throw "MercuryGram checksum mismatch. Expected $expected, got $actual. Nothing was installed."
    }
    Write-Ok 'MercuryGram checksum verified.'

    if (Test-Path $destination) {
        Remove-Item -LiteralPath $destination -Recurse -Force
    }
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    Expand-Archive -LiteralPath $zip -DestinationPath $destination -Force
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue

    if (-not (Test-Path $exe)) {
        throw "MercuryGram extracted, but $exe was not found."
    }

    $startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\MercuryGram.lnk'
    New-Shortcut -Path $startMenu -Target $exe -WorkingDirectory (Split-Path -Parent $exe) -IconLocation $exe
    $desktop = Join-Path ([Environment]::GetFolderPath('Desktop')) 'MercuryGram.lnk'
    New-Shortcut -Path $desktop -Target $exe -WorkingDirectory (Split-Path -Parent $exe) -IconLocation $exe
    Write-Ok "MercuryGram $version installed."
}

function Install-VSCodiumExtensions {
    $codium = Get-CommandPath 'codium'
    if (-not $codium) {
        Write-Skip 'VSCodium is not installed; extensions skipped.'
        return
    }

    $listPath = Join-Path $script:ConfigRoot 'vscodium\extensions.txt'
    if (-not (Test-Path $listPath)) {
        Write-Warn "Extension list not found: $listPath"
        return
    }

    $installed = @()
    if (-not $script:DryRun) {
        $installed = @(& codium --list-extensions 2>$null)
    }

    $remove = @('eamodio.gitlens')
    foreach ($extension in $remove) {
        if ($installed -contains $extension) {
            if ($script:DryRun) {
                Write-Detail "[dry-run] codium --uninstall-extension $extension"
            }
            else {
                Invoke-External -FilePath $codium -ArgumentList @('--uninstall-extension', $extension) -AllowFailure | Out-Null
                Write-Ok "removed telemetry-heavy extension: $extension"
            }
        }
    }

    $wanted = Get-Content $listPath |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and -not $_.StartsWith('#') }

    foreach ($extension in $wanted) {
        if ($installed -contains $extension) {
            Write-Skip "$extension already installed."
            continue
        }
        if ($script:DryRun) {
            Write-Detail "[dry-run] codium --install-extension $extension"
            continue
        }
        $code = Invoke-External -FilePath $codium -ArgumentList @('--install-extension', $extension, '--force') -AllowFailure
        if ($code -eq 0) { Write-Ok "extension: $extension" }
        else { Write-Warn "extension $extension returned exit code $code." }
    }
}

function Invoke-Apps {
    Write-Step 'Apps: editors, runtimes, and daily tools'

    if (-not (Get-CommandPath 'winget')) {
        Write-Skip 'winget is unavailable. Skipping winget packages; manual IDs are in README.md.'
        Write-Detail 'MercuryGram and VSCodium extensions are still handled below.'
    }
    else {
        Install-AppPackage -Id 'VSCodium.VSCodium' -Name 'VSCodium' -Command 'codium'
        Install-AppPackage -Id 'Git.Git' -Name 'Git' -Command 'git'
        Install-AppPackage -Id 'GitHub.cli' -Name 'GitHub CLI' -Command 'gh'

        if (-not (Get-CommandPath 'node')) {
            Install-AppPackage -Id 'OpenJS.NodeJS.LTS' -Name 'Node.js LTS'
        }
        else {
            Write-Skip "Node.js already available ($((& node --version 2>$null) -join ''))"
        }

        if (-not (Get-CommandPath 'python') -and -not (Get-CommandPath 'py')) {
            Install-AppPackage -Id 'Python.Python.3.12' -Name 'Python 3.12'
        }
        else {
            Write-Skip 'Python is already available.'
        }

        if (Test-Path 'C:\Program Files\7-Zip\7z.exe') {
            Write-Skip '7-Zip is already installed.'
        }
        else {
            Install-AppPackage -Id '7zip.7zip' -Name '7-Zip'
        }

        Install-AppPackage -Id 'Microsoft.VCRedist.2015+.x64' -Name 'Visual C++ 2015-2022 x64'
        Install-AppPackage -Id 'Microsoft.VCRedist.2015+.x86' -Name 'Visual C++ 2015-2022 x86'
        Install-AppPackage -Id 'Microsoft.EdgeWebView2Runtime' -Name 'WebView2 Runtime'

        Install-AppPackage -Id 'Microsoft.PowerToys' -Name 'PowerToys'
        Install-AppPackage -Id 'KeePassXCTeam.KeePassXC' -Name 'KeePassXC'
        Install-AppPackage -Id 'LibreWolf.LibreWolf' -Name 'LibreWolf'
        Install-AppPackage -Id 'ONLYOFFICE.DesktopEditors' -Name 'ONLYOFFICE'
        Install-AppPackage -Id 'Vencord.Vesktop' -Name 'Vesktop'
        Install-AppPackage -Id 'Microsoft.WindowsTerminal' -Name 'Windows Terminal' -Command 'wt'

        if (Test-FontInstalled -Pattern 'JetBrainsMono Nerd Font') {
            Write-Skip 'JetBrains Mono Nerd Font is already installed.'
        }
        else {
            Install-AppPackage -Id 'DEVCOM.JetBrainsMonoNerdFont' -Name 'JetBrains Mono Nerd Font'
        }
    }

    Write-Step 'Apps: MercuryGram portable'
    Install-MercuryGram

    Write-Step 'Apps: VSCodium extensions'
    Install-VSCodiumExtensions
}
