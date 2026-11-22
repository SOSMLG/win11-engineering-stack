function Set-TerminalTheme {
    $path = Get-TerminalSettingsPath
    if (-not $path) {
        Write-Skip 'Windows Terminal settings not found; terminal theme skipped.'
        return
    }

    $scheme = @{
        name                = 'Graphite Amber'
        background          = '#16181D'
        foreground          = '#D8D3C8'
        cursorColor         = '#E8A33D'
        selectionBackground = '#3A352C'
        black               = '#25272C'
        red                 = '#C97064'
        green               = '#8FB57A'
        yellow              = '#E8A33D'
        blue                = '#7E9DB5'
        purple              = '#A78BB5'
        cyan                = '#79A9A6'
        white               = '#D8D3C8'
        brightBlack         = '#454A52'
        brightRed           = '#DF9588'
        brightGreen         = '#A7C99A'
        brightYellow        = '#F0BC6D'
        brightBlue          = '#98B4C8'
        brightPurple        = '#C0A8CB'
        brightCyan          = '#9CC4C1'
        brightWhite         = '#F0ECE2'
    }

    $settings = @{}
    if (Test-Path $path) {
        try {
            $settings = ConvertTo-DeepHashtable (Get-Content $path -Raw | ConvertFrom-Json)
        }
        catch {
            Write-Warn "Terminal settings are invalid JSON; replacing: $path"
            $settings = @{}
        }
    }

    if (-not $settings.ContainsKey('schemes') -or $null -eq $settings['schemes']) {
        $settings['schemes'] = @()
    }

    $schemes = @($settings['schemes'])
    $names = @($schemes | ForEach-Object { Get-PropValue $_ 'name' '' })
    if ($names -notcontains 'Graphite Amber') {
        $schemes += $scheme
    }
    $settings['schemes'] = $schemes

    if (-not $settings.ContainsKey('profiles') -or $null -eq $settings['profiles']) {
        $settings['profiles'] = @{}
    }
    $profiles = ConvertTo-DeepHashtable $settings['profiles']
    if (-not $profiles.ContainsKey('defaults') -or $null -eq $profiles['defaults']) {
        $profiles['defaults'] = @{}
    }
    $defaults = ConvertTo-DeepHashtable $profiles['defaults']
    $defaults['font'] = @{
        face = 'JetBrainsMono Nerd Font Mono'
        size = 11
    }
    $defaults['startingDirectory'] = '%USERPROFILE%'
    $defaults['colorScheme'] = 'Graphite Amber'
    $defaults['useAcrylic'] = $false
    $defaults['opacity'] = 100
    $profiles['defaults'] = $defaults
    $settings['profiles'] = $profiles
    if (-not $settings.ContainsKey('defaultProfile')) {
        $settings['defaultProfile'] = '{61c54bbd-c2c6-5271-96e7-009a87ff44bf}'
    }
    $settings['theme'] = 'dark'

    Write-JsonFile -Path $path -Value $settings -NoMerge
    if ($script:DryRun) { Write-Detail "[dry-run] terminal theme would be written: $path" }
    else { Write-Ok "terminal theme applied: $path" }
}

function Install-VSCodiumTheme {
    $source = Join-Path $script:RepoRoot 'VSCodium\graphite-amber-theme'
    if (-not (Test-Path $source)) {
        Write-Warn "VSCodium theme folder missing: $source"
        return
    }

    $target = Join-Path $env:USERPROFILE '.vscode-oss\extensions\xfcemlg.graphite-amber-theme-0.6.0'
    if (Test-Path $target) {
        Write-Skip "VSCodium Graphite Amber theme exists: $target"
        return
    }
    if ($script:DryRun) {
        Write-Detail "[dry-run] install VSCodium Graphite Amber theme: $target"
        return
    }

    New-Item -ItemType Directory -Path $target -Force | Out-Null
    Get-ChildItem -LiteralPath $source | Copy-Item -Destination $target -Recurse -Force
    Write-Ok "VSCodium Graphite Amber theme installed: $target"
}

function Set-WindowsTheme {
    $personalize = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
    Set-RegistryValue -Path $personalize -Name 'AppsUseLightTheme' -Value 1 -Type DWord
    Set-RegistryValue -Path $personalize -Name 'SystemUsesLightTheme' -Value 1 -Type DWord
    Set-RegistryValue -Path $personalize -Name 'EnableTransparency' -Value 0 -Type DWord
    Set-RegistryValue -Path $personalize -Name 'ColorPrevalence' -Value 0 -Type DWord

    Set-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' -Name 'VisualFXSetting' -Value 2 -Type DWord
    Set-RegistryValue -Path 'HKCU:\Control Panel\Desktop\WindowMetrics' -Name 'MinAnimate' -Value '0' -Type String

    $dwm = 'HKCU:\Software\Microsoft\Windows\DWM'
    Set-RegistryValue -Path $dwm -Name 'ColorizationColor' -Value 3303580477 -Type DWord
    Set-RegistryValue -Path $dwm -Name 'ColorizationAfterglow' -Value 3303580477 -Type DWord
    Set-RegistryValue -Path $dwm -Name 'AccentColorInactive' -Value 3302136111 -Type DWord

    Set-RegistryValue -Path 'HKCU:\Control Panel\Desktop' -Name 'TileWallpaper' -Value '0' -Type String
    Set-RegistryValue -Path 'HKCU:\Control Panel\Colors' -Name 'Background' -Value '232 236 242' -Type String
}

function Set-PowerShellProfile {
    $content = @'
# UTF-8 everywhere, including native tools and Python.
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [Console]::OutputEncoding
$PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'
$env:PYTHONUTF8 = '1'
'@

    $paths = @(
        (Join-Path $env:USERPROFILE 'Documents\PowerShell\profile.ps1'),
        (Join-Path $env:USERPROFILE 'Documents\WindowsPowerShell\profile.ps1')
    )

    foreach ($path in $paths) {
        Set-ManagedBlock -Path $path -Begin '# >>> win11-engineering-stack >>>' -End '# <<< win11-engineering-stack <<<' -Content $content
    }
}

function Invoke-Theme {
    Write-Step 'Theme: light shell, graphite amber editor'

    Set-WindowsTheme

    if (Test-FontInstalled -Pattern 'JetBrainsMono Nerd Font') {
        Write-Ok 'JetBrains Mono Nerd Font is installed.'
    }
    else {
        Write-Warn 'JetBrains Mono Nerd Font is missing; editors fall back to Cascadia Mono or Consolas.'
        Write-Detail 'Install it manually, or restore winget/App Installer and run: .\scripts\Install.ps1 -Only apps'
    }

    Set-TerminalTheme
    Install-VSCodiumTheme
    Set-PowerShellProfile

    Write-Detail 'Windows UI changes apply at the next sign-in.'
    Write-Detail 'Engineering apps keep their native light theme; only editors and terminals are dark.'
}
