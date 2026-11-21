function Set-TerminalTheme {
    $path = Get-TerminalSettingsPath
    if (-not $path) {
        Write-Skip 'Windows Terminal settings not found; terminal theme skipped.'
        return
    }

    $scheme = @{
        name                = 'Catppuccin Mocha'
        background          = '#1E1E2E'
        foreground          = '#CDD6F4'
        cursorColor         = '#F5E0DC'
        selectionBackground = '#585B70'
        black               = '#45475A'
        red                 = '#F38BA8'
        green               = '#A6E3A1'
        yellow              = '#F9E2AF'
        blue                = '#89B4FA'
        purple              = '#CBA6F7'
        cyan                = '#94E2D5'
        white               = '#BAC2DE'
        brightBlack         = '#585B70'
        brightRed           = '#F38BA8'
        brightGreen         = '#A6E3A1'
        brightYellow        = '#F9E2AF'
        brightBlue          = '#89B4FA'
        brightPurple        = '#CBA6F7'
        brightCyan          = '#94E2D5'
        brightWhite         = '#A6ADC8'
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
    if ($names -notcontains 'Catppuccin Mocha') {
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
    $defaults['colorScheme'] = 'Catppuccin Mocha'
    $defaults['useAcrylic'] = $false
    $defaults['opacity'] = 100
    $profiles['defaults'] = $defaults
    $settings['profiles'] = $profiles
    $settings['theme'] = 'dark'

    Write-JsonFile -Path $path -Value $settings -NoMerge
    Write-Ok "terminal theme applied: $path"
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
    Set-RegistryValue -Path $dwm -Name 'ColorizationColor' -Value 3225450676 -Type DWord
    Set-RegistryValue -Path $dwm -Name 'ColorizationAfterglow' -Value 3225450676 -Type DWord
    Set-RegistryValue -Path $dwm -Name 'AccentColorInactive' -Value 3235372776 -Type DWord

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
    Write-Step 'Theme: light shell, dark editor'

    Set-WindowsTheme

    if (Test-FontInstalled -Pattern 'JetBrainsMono Nerd Font') {
        Write-Ok 'JetBrains Mono Nerd Font is installed.'
    }
    else {
        Write-Warn 'JetBrains Mono Nerd Font is missing; editors fall back to Cascadia Mono or Consolas.'
        Write-Detail 'Install it manually, or restore winget/App Installer and run: .\scripts\Install.ps1 -Only apps'
    }

    Set-TerminalTheme
    Set-PowerShellProfile

    Write-Detail 'Windows UI changes apply at the next sign-in.'
    Write-Detail 'Engineering apps keep their native light theme; only editors and terminals are dark.'
}
