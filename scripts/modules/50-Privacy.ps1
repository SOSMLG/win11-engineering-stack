function Set-GitConfiguration {
    if (-not (Get-CommandPath 'git')) {
        Write-Skip 'Git is not installed; configuration skipped.'
        return
    }

    $name = (& git config --global --get user.name 2>$null) -join ''
    $email = (& git config --global --get user.email 2>$null) -join ''

    if (-not $name -and $script:GitName) {
        Invoke-External -FilePath 'git' -ArgumentList @('config', '--global', 'user.name', $script:GitName) | Out-Null
        $name = $script:GitName
    }
    if (-not $email -and $script:GitEmail) {
        Invoke-External -FilePath 'git' -ArgumentList @('config', '--global', 'user.email', $script:GitEmail) | Out-Null
        $email = $script:GitEmail
    }

    if (-not $name) { Write-Warn 'Git user.name is unset. Rerun with -GitName "Your Name".' }
    if (-not $email) { Write-Warn 'Git user.email is unset. Rerun with -GitEmail and your own address.' }
    if ($name -and $email) { Write-Ok "Git identity: $name (email set)" }

    $settings = @(
        @('init.defaultBranch', 'main'),
        @('pull.rebase', 'true'),
        @('core.longpaths', 'true'),
        @('core.autocrlf', 'true'),
        @('alias.unstage', 'reset HEAD --'),
        @('alias.last', 'log -1 HEAD'),
        @('alias.amend', 'commit --amend --no-edit'),
        @('alias.lg', 'log --oneline --graph --decorate')
    )

    $codium = Get-CommandPath 'codium'
    if ($codium) {
        $settings += , @('core.editor', 'codium --wait')
    }

    foreach ($setting in $settings) {
        $key = $setting[0]
        $value = $setting[1]
        $current = (& git config --global --get $key 2>$null) -join ''
        if ($current -eq $value) {
            Write-Skip "git $key already $value"
            continue
        }
        if ($script:DryRun) {
            Write-Detail "[dry-run] git config --global $key `"$value`""
            continue
        }
        Invoke-External -FilePath 'git' -ArgumentList @('config', '--global', $key, $value) | Out-Null
        Write-Ok "git $key = $value"
    }
}

function Set-GhConfiguration {
    if (-not (Get-CommandPath 'gh')) {
        Write-Skip 'GitHub CLI is not installed; configuration skipped.'
        return
    }

    $current = (& gh config get telemetry 2>$null) -join ''
    if ($current -eq 'disabled') {
        Write-Skip 'gh telemetry already disabled.'
    }
    elseif ($script:DryRun) {
        Write-Detail '[dry-run] gh config set telemetry disabled'
    }
    else {
        Invoke-External -FilePath 'gh' -ArgumentList @('config', 'set', 'telemetry', 'disabled') -AllowFailure | Out-Null
        Write-Ok 'gh telemetry disabled.'
    }

    $protocol = (& gh config get git_protocol 2>$null) -join ''
    if ($protocol -eq 'ssh') {
        Write-Skip 'gh git protocol already ssh.'
    }
    elseif ($script:DryRun) {
        Write-Detail '[dry-run] gh config set git_protocol ssh'
    }
    else {
        Invoke-External -FilePath 'gh' -ArgumentList @('config', 'set', 'git_protocol', 'ssh') -AllowFailure | Out-Null
        Write-Ok 'gh git protocol set to ssh.'
    }

    $status = & gh auth status 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warn 'gh is not authenticated. Run: gh auth login'
    }
    else {
        $account = ($status | Select-Object -First 1) -join ''
        Write-Detail $account
    }

    $publicKey = Join-Path $env:USERPROFILE '.ssh\id_ed25519.pub'
    if (Test-Path $publicKey) {
        Write-Detail "SSH public key: $publicKey"
        Write-Detail 'If GitHub does not know it yet: gh ssh-key add $HOME\.ssh\id_ed25519.pub'
    }
    else {
        Write-Skip 'No Ed25519 SSH key found. Create one with ssh-keygen -t ed25519 -C "your own label"'
    }
}

function Set-WindowsPrivacy {
    $values = @(
        @('HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo', 'Enabled', 0),
        @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy', 'TailoredExperiencesWithDiagnosticDataEnabled', 0),
        @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy', 'PublishUserActivities', 0),
        @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy', 'UploadUserActivities', 0),
        @('HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager', 'SoftLandingEnabled', 0),
        @('HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager', 'SubscribedContent-338389Enabled', 0),
        @('HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager', 'SystemPaneSuggestionsEnabled', 0),
        @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection', 'AllowTelemetry', 0)
    )

    foreach ($entry in $values) {
        Set-RegistryValue -Path $entry[0] -Name $entry[1] -Value $entry[2] -Type DWord
    }
}

function Set-KeepassVaultFolder {
    $vault = Join-Path $env:USERPROFILE 'Documents\Vaults'
    if (Test-Path $vault) {
        Write-Skip "vault folder exists: $vault"
        return
    }
    if ($script:DryRun) {
        Write-Detail "[dry-run] create $vault"
        return
    }
    New-Item -ItemType Directory -Path $vault -Force | Out-Null
    Write-Ok "created $vault"
    Write-Detail 'Create the .kdbx database in KeePassXC; this script never stores credentials.'
}

function Get-LibreWolfPath {
    $candidates = @(
        (Get-CommandPath 'librewolf'),
        'C:\Program Files\LibreWolf\librewolf.exe',
        (Join-Path $env:LOCALAPPDATA 'LibreWolf\librewolf.exe')
    )

    $appPath = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\librewolf.exe' -ErrorAction SilentlyContinue
    if ($appPath) {
        $candidates += (Get-PropValue $appPath '(default)' $null)
    }

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path $candidate)) { return $candidate }
    }
    return $null
}

function Set-LibreWolfProfiles {
    $librewolf = Get-LibreWolfPath
    if (-not $librewolf) {
        Write-Skip 'LibreWolf is not installed; profiles skipped.'
        return
    }

    $dataRoot = Join-Path $env:APPDATA 'LibreWolf'
    $profilesRoot = Join-Path $dataRoot 'Profiles'
    $iniPath = Join-Path $dataRoot 'profiles.ini'
    $existing = ''
    if (Test-Path $iniPath) { $existing = Get-Content $iniPath -Raw }

    $profiles = @('personal', 'uni', 'social')
    $shortcutFolder = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\LibreWolf Profiles'

    if (-not $script:DryRun -and -not (Test-Path $profilesRoot)) {
        New-Item -ItemType Directory -Path $profilesRoot -Force | Out-Null
    }

    foreach ($profile in $profiles) {
        $profilePath = Join-Path $profilesRoot $profile
        $known = $existing -match ('(?m)^Name=' + [regex]::Escape($profile) + '$')

        if ($known -and (Test-Path $profilePath)) {
            Write-Skip "LibreWolf profile exists: $profile"
        }
        elseif ($script:DryRun) {
            Write-Detail "[dry-run] create LibreWolf profile $profile at $profilePath"
        }
        else {
            Invoke-External -FilePath $librewolf -ArgumentList @('-CreateProfile', "$profile $profilePath") -AllowFailure | Out-Null
            Write-Ok "LibreWolf profile: $profile"
        }

        $shortcut = Join-Path $shortcutFolder "$profile.lnk"
        if (Test-Path $shortcut) {
            Write-Skip "shortcut exists: $shortcut"
        }
        else {
            New-Shortcut -Path $shortcut -Target $librewolf -Arguments "-P `"$profile`" -no-remote" -IconLocation $librewolf
        }
    }

    Write-Detail 'Sign in to each profile separately; never reuse a personal account in the uni or social profile.'
}

function Invoke-Privacy {
    Write-Step 'Privacy: Git, GitHub, Windows, browsers'
    Assert-Admin

    Set-GitConfiguration
    Set-GhConfiguration
    Set-WindowsPrivacy
    Set-KeepassVaultFolder
    Set-LibreWolfProfiles
}
