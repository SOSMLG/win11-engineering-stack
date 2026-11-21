function Add-ValidationResult {
    param(
        [ValidateSet('PASS', 'FAIL', 'SKIP')][string]$Status,
        [string]$Check,
        [string]$Detail = ''
    )

    $script:ValidationResults += [pscustomobject]@{
        Status = $Status
        Check  = $Check
        Detail = $Detail
    }
}

function Test-JsonConfigs {
    $files = @(Get-ChildItem -Path $script:ConfigRoot -Recurse -Filter '*.json' -ErrorAction SilentlyContinue)
    $bad = @()
    foreach ($file in $files) {
        try {
            Get-Content $file.FullName -Raw | ConvertFrom-Json | Out-Null
        }
        catch {
            $bad += $file.Name
        }
    }
    if ($bad.Count -eq 0) {
        Add-ValidationResult -Status PASS -Check 'config JSON' -Detail "$($files.Count) files parse"
    }
    else {
        Add-ValidationResult -Status FAIL -Check 'config JSON' -Detail ($bad -join ', ')
    }
}

function Invoke-Validate {
    Write-Step 'Validate: read-only checks'

    $script:ValidationResults = @()
    $guardrails = Get-ImageGuardrails
    $os = Get-CimInstance -ClassName Win32_OperatingSystem

    Add-ValidationResult -Status PASS -Check 'OS' -Detail "$($os.Caption) $($os.Version)"

    if ($guardrails.DefenderCmdlet -or $guardrails.DefenderService) {
        Add-ValidationResult -Status PASS -Check 'Defender present' -Detail 'service or cmdlets found'
    }
    else {
        Add-ValidationResult -Status FAIL -Check 'Defender present' -Detail 'image has no Defender'
    }

    if ($guardrails.WinSxS) {
        Add-ValidationResult -Status PASS -Check 'WinSxS' -Detail 'component store present'
    }
    else {
        Add-ValidationResult -Status FAIL -Check 'WinSxS' -Detail 'optional features cannot be serviced'
    }

    if ($guardrails.Winget) {
        Add-ValidationResult -Status PASS -Check 'winget' -Detail 'available'
    }
    else {
        Add-ValidationResult -Status SKIP -Check 'winget' -Detail 'missing; manual IDs are in README.md'
    }

    if ($null -ne (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue)) {
        try {
            $status = Get-MpComputerStatus
            if ($status.RealTimeProtectionEnabled) {
                Add-ValidationResult -Status PASS -Check 'Defender real-time' -Detail 'enabled'
            }
            else {
                Add-ValidationResult -Status FAIL -Check 'Defender real-time' -Detail 'disabled'
            }
        }
        catch {
            Add-ValidationResult -Status SKIP -Check 'Defender real-time' -Detail $_.Exception.Message
        }
    }
    else {
        Add-ValidationResult -Status SKIP -Check 'Defender real-time' -Detail 'cmdlets unavailable'
    }

    $featureChecks = @('NetFx3', 'IIS-WebServerRole', 'MSMQ-Server', 'WCF-HTTP-Activation45')
    foreach ($feature in $featureChecks) {
        $state = Get-OptionalFeatureState -Name $feature
        if ($state -eq 'Enabled') {
            Add-ValidationResult -Status PASS -Check $feature -Detail 'enabled'
        }
        elseif ($state -eq 'Unknown') {
            Add-ValidationResult -Status SKIP -Check $feature -Detail 'needs elevation'
        }
        else {
            Add-ValidationResult -Status FAIL -Check $feature -Detail $state
        }
    }

    $longPaths = Get-PropValue (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -ErrorAction SilentlyContinue) 'LongPathsEnabled' 0
    if ($longPaths -eq 1) {
        Add-ValidationResult -Status PASS -Check 'Long paths' -Detail 'enabled'
    }
    else {
        Add-ValidationResult -Status FAIL -Check 'Long paths' -Detail 'disabled'
    }

    try {
        $rule = Get-NetFirewallRule -DisplayName 'TIA Portal S7 inbound (TCP 102)' -ErrorAction Stop
    }
    catch {
        $rule = $null
    }
    if ($rule) {
        Add-ValidationResult -Status PASS -Check 'S7 firewall' -Detail 'TCP 102 inbound rule present'
    }
    else {
        Add-ValidationResult -Status FAIL -Check 'S7 firewall' -Detail 'TCP 102 rule missing'
    }

    $codium = Get-CommandPath 'codium'
    if ($codium) {
        Add-ValidationResult -Status PASS -Check 'VSCodium' -Detail ((& codium --version 2>$null) -join ' ')
        $installed = @(& codium --list-extensions 2>$null)
        $required = @('ms-python.python', 'charliermarsh.ruff', 'detachhead.basedpyright')
        $missing = @($required | Where-Object { $installed -notcontains $_ })
        if ($missing.Count -eq 0) {
            Add-ValidationResult -Status PASS -Check 'VSCodium extensions' -Detail 'required set installed'
        }
        else {
            Add-ValidationResult -Status FAIL -Check 'VSCodium extensions' -Detail ("missing: " + ($missing -join ', '))
        }
    }
    else {
        Add-ValidationResult -Status SKIP -Check 'VSCodium' -Detail 'not installed'
    }

    if (Get-CommandPath 'git') {
        $name = (& git config --global --get user.name 2>$null) -join ''
        $email = (& git config --global --get user.email 2>$null) -join ''
        if ($name -and $email) {
            Add-ValidationResult -Status PASS -Check 'Git identity' -Detail "$name (email set)"
        }
        else {
            Add-ValidationResult -Status FAIL -Check 'Git identity' -Detail 'user.name or user.email missing'
        }
    }
    else {
        Add-ValidationResult -Status SKIP -Check 'Git identity' -Detail 'Git not installed'
    }

    if (Get-CommandPath 'gh') {
        $null = & gh auth status 2>&1
        if ($LASTEXITCODE -eq 0) {
            Add-ValidationResult -Status PASS -Check 'gh auth' -Detail 'authenticated'
        }
        else {
            Add-ValidationResult -Status FAIL -Check 'gh auth' -Detail 'not authenticated'
        }

    }
    else {
        Add-ValidationResult -Status SKIP -Check 'gh' -Detail 'not installed'
    }

    if (Test-OmniRoute) {
        Add-ValidationResult -Status PASS -Check 'OmniRoute' -Detail '127.0.0.1:20128 responds'
    }
    else {
        Add-ValidationResult -Status FAIL -Check 'OmniRoute' -Detail 'not responding'
    }

    $listeners = @(Get-NetTCPConnection -LocalPort 20128 -State Listen -ErrorAction SilentlyContinue)
    if ($listeners.Count -gt 0) {
        $public = @($listeners | Where-Object { $_.LocalAddress -notin @('127.0.0.1', '::1') })
        if ($public.Count -eq 0) {
            Add-ValidationResult -Status PASS -Check 'OmniRoute binding' -Detail 'loopback only'
        }
        else {
            Add-ValidationResult -Status FAIL -Check 'OmniRoute binding' -Detail ("listening on " + (($public.LocalAddress | Select-Object -Unique) -join ', '))
        }
    }

    $opencodeConfig = Join-Path $env:USERPROFILE '.config\opencode\opencode.json'
    if (Test-Path $opencodeConfig) {
        try {
            $config = Get-Content $opencodeConfig -Raw | ConvertFrom-Json
            $providers = Get-PropValue $config 'providers' $null
            $legacy = Get-PropValue $config 'provider' $null
            $model = Get-PropValue $config 'model' ''
            if ($null -ne $providers -and $null -ne (Get-PropValue $providers 'omniroute' $null) -and $null -eq $legacy) {
                Add-ValidationResult -Status PASS -Check 'OpenCode provider' -Detail "V2 shape, model $model"
            }
            else {
                Add-ValidationResult -Status FAIL -Check 'OpenCode provider' -Detail 'not migrated to providers (plural)'
            }
        }
        catch {
            Add-ValidationResult -Status FAIL -Check 'OpenCode provider' -Detail 'config is invalid JSON'
        }
    }
    else {
        Add-ValidationResult -Status SKIP -Check 'OpenCode provider' -Detail 'config not found'
    }

    $personalize = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -ErrorAction SilentlyContinue
    if ((Get-PropValue $personalize 'AppsUseLightTheme' 0) -eq 1 -and (Get-PropValue $personalize 'EnableTransparency' 1) -eq 0) {
        Add-ValidationResult -Status PASS -Check 'Theme' -Detail 'light mode, transparency off'
    }
    else {
        Add-ValidationResult -Status FAIL -Check 'Theme' -Detail 'registry values not applied'
    }

    if (Test-FontInstalled -Pattern 'JetBrainsMono Nerd Font') {
        Add-ValidationResult -Status PASS -Check 'Font' -Detail 'JetBrains Mono Nerd Font'
    }
    else {
        Add-ValidationResult -Status FAIL -Check 'Font' -Detail 'JetBrains Mono Nerd Font missing'
    }

    $tia = Get-TiaRoot
    if ($tia) {
        Add-ValidationResult -Status PASS -Check 'TIA Portal' -Detail $tia
    }
    else {
        Add-ValidationResult -Status SKIP -Check 'TIA Portal' -Detail 'not installed'
    }

    $matlab = Get-MatlabRoot
    if ($matlab) {
        $matlabRoot = [Environment]::GetEnvironmentVariable('MATLABROOT', 'Machine')
        if ($matlabRoot -eq $matlab) {
            Add-ValidationResult -Status PASS -Check 'MATLAB' -Detail "MATLABROOT=$matlabRoot"
        }
        else {
            Add-ValidationResult -Status FAIL -Check 'MATLAB' -Detail 'MATLABROOT missing or stale'
        }
    }
    else {
        Add-ValidationResult -Status SKIP -Check 'MATLAB' -Detail 'not installed'
    }

    if (Test-RebootPending) {
        Add-ValidationResult -Status SKIP -Check 'Reboot' -Detail 'pending'
    }
    else {
        Add-ValidationResult -Status PASS -Check 'Reboot' -Detail 'none pending'
    }

    Test-JsonConfigs

    $script:ValidationResults | Format-Table -AutoSize | Out-String | Write-Host

    $failures = @($script:ValidationResults | Where-Object { $_.Status -eq 'FAIL' })
    $skips = @($script:ValidationResults | Where-Object { $_.Status -eq 'SKIP' })
    Write-Host ("{0} passed, {1} failed, {2} skipped" -f ($script:ValidationResults.Count - $failures.Count - $skips.Count), $failures.Count, $skips.Count)

    $script:ValidationFailed = ($failures.Count -gt 0)
}
