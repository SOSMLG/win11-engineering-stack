function Enable-OptionalFeatureSafe {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$Source
    )

    $state = Get-OptionalFeatureState -Name $Name
    if ($state -eq 'Enabled') {
        Write-Skip "$Name already enabled."
        return $false
    }
    if ($state -eq 'Unknown') {
        if ($script:DryRun -and -not (Test-Admin)) {
            Write-Detail "[dry-run] enable feature $Name (state unknown without elevation)"
            return $false
        }
        Write-Warn "$Name state is unknown; skipping. This usually means WinSxS is missing or elevation failed."
        return $false
    }

    $arguments = @{
        Online      = $true
        FeatureName = $Name
        All         = $true
        NoRestart   = $true
        ErrorAction = 'Stop'
    }
    if ($Source -and (Test-Path $Source)) {
        $arguments['Source'] = $Source
        $arguments['LimitAccess'] = $true
    }

    if ($script:DryRun) {
        Write-Detail "[dry-run] enable feature $Name"
        return $false
    }

    try {
        $result = Enable-WindowsOptionalFeature @arguments
        Write-Ok "$Name enabled."
        return [bool]$result.RestartNeeded
    }
    catch {
        Write-Fail "$Name could not be enabled: $($_.Exception.Message)"
        return $false
    }
}

function Set-LongPaths {
    $key = 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'
    $current = Get-PropValue (Get-ItemProperty $key -ErrorAction SilentlyContinue) 'LongPathsEnabled' 0
    if ($current -eq 1) {
        Write-Skip 'Long paths already enabled.'
        return
    }
    if ($script:DryRun) {
        Write-Detail '[dry-run] set LongPathsEnabled=1'
        return
    }
    Set-ItemProperty -Path $key -Name LongPathsEnabled -Value 1 -Type DWord
    Write-Ok 'Long paths enabled.'
}

function Set-S7FirewallRules {
    $rules = @(
        @{ Name = 'TIA Portal S7 inbound (TCP 102)'; Direction = 'Inbound' },
        @{ Name = 'TIA Portal S7 outbound (TCP 102)'; Direction = 'Outbound' }
    )
    foreach ($rule in $rules) {
        $existing = Get-NetFirewallRule -DisplayName $rule.Name -ErrorAction SilentlyContinue
        if ($existing) {
            if ($existing.Enabled -eq 'True') {
                Write-Skip "Firewall rule already present: $($rule.Name)"
            }
            elseif ($script:DryRun) {
                Write-Detail "[dry-run] enable firewall rule: $($rule.Name)"
            }
            else {
                Enable-NetFirewallRule -DisplayName $rule.Name | Out-Null
                Write-Ok "Firewall rule enabled: $($rule.Name)"
            }
            continue
        }
        if ($script:DryRun) {
            Write-Detail "[dry-run] add firewall rule: $($rule.Name)"
            continue
        }
        New-NetFirewallRule `
            -DisplayName $rule.Name `
            -Direction $rule.Direction `
            -Action Allow `
            -Protocol TCP `
            -LocalPort 102 `
            -Profile Domain, Private `
            -Description 'S7 engineering communication for TIA Portal.' | Out-Null
        Write-Ok "Firewall rule: $($rule.Name)"
    }
}

function Enable-NetworkDiscovery {
    try {
        $rules = Get-NetFirewallRule -DisplayGroup 'Network Discovery' -ErrorAction Stop
        $enabled = @($rules | Where-Object { $_.Enabled -eq 'True' })
        if ($enabled.Count -eq $rules.Count) {
            Write-Skip 'Network discovery rules already enabled.'
        }
        elseif ($script:DryRun) {
            Write-Detail '[dry-run] enable Network Discovery firewall group (private/domain).'
        }
        else {
            Set-NetFirewallRule -DisplayGroup 'Network Discovery' -Profile Private, Domain -Enabled True
            Write-Ok 'Network discovery enabled for private and domain networks.'
        }
    }
    catch {
        Write-Warn "Network discovery rules could not be updated: $($_.Exception.Message)"
    }

    $service = Get-Service -Name FDResPub -ErrorAction SilentlyContinue
    if ($service) {
        if ($service.StartType -eq 'Automatic' -and $service.Status -eq 'Running') {
            Write-Skip 'Function Discovery Resource Publication already running.'
        }
        elseif ($script:DryRun) {
            Write-Detail '[dry-run] set FDResPub to Automatic and start it.'
        }
        else {
            Set-Service -Name FDResPub -StartupType Automatic
            Start-Service -Name FDResPub -ErrorAction SilentlyContinue
            Write-Ok 'Function Discovery Resource Publication started.'
        }
    }
}

function Optimize-PlcAdapter {
    param([string]$Name)

    if (-not $Name) {
        Write-Skip 'No -PlcAdapter supplied; NIC tuning skipped.'
        Write-Detail 'Re-run with -PlcAdapter "Ethernet" after connecting the PLC network adapter.'
        return
    }

    $adapter = Get-NetAdapter -Name $Name -ErrorAction SilentlyContinue
    if (-not $adapter) {
        Write-Warn "Adapter '$Name' was not found; NIC tuning skipped."
        return
    }

    Write-Detail "Tuning adapter: $($adapter.InterfaceDescription)"

    if ($script:DryRun) {
        Write-Detail "[dry-run] disable power management on $Name"
    }
    else {
        try {
            Disable-NetAdapterPowerManagement -Name $Name -ErrorAction Stop
            Write-Ok 'Adapter power management disabled.'
        }
        catch {
            Write-Warn "Power management could not be disabled: $($_.Exception.Message)"
        }
    }

    $patterns = 'Energy|Green|EEE|Interrupt Moderation|Power Save|Selective Suspend'
    $properties = Get-NetAdapterAdvancedProperty -Name $Name -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -match $patterns }

    foreach ($property in $properties) {
        $valid = @($property.ValidDisplayValues)
        $target = $null
        if ($valid -contains 'Disabled') { $target = 'Disabled' }
        elseif ($valid -contains 'Off') { $target = 'Off' }

        if (-not $target) {
            Write-Skip "No disable value for '$($property.DisplayName)'."
            continue
        }
        if ($property.DisplayValue -eq $target) {
            Write-Skip "$($property.DisplayName) already $target."
            continue
        }
        if ($script:DryRun) {
            Write-Detail "[dry-run] $($property.DisplayName) -> $target"
            continue
        }
        try {
            Set-NetAdapterAdvancedProperty -Name $Name -DisplayName $property.DisplayName -DisplayValue $target -ErrorAction Stop
            Write-Ok "$($property.DisplayName) -> $target"
        }
        catch {
            Write-Warn "$($property.DisplayName) could not be changed: $($_.Exception.Message)"
        }
    }
}

function Invoke-OS {
    Write-Step 'OS: engineering prerequisites'
    Assert-Admin

    $source = $null
    if ($script:SxsPath) {
        $source = $script:SxsPath
        if (-not (Test-Path $source)) {
            Write-Warn "SxsPath does not exist: $source"
            $source = $null
        }
        else {
            Write-Detail "feature source: $source"
        }
    }

    $features = @(
        'NetFx3',
        'IIS-WebServerRole',
        'IIS-WebServer',
        'IIS-CommonHttpFeatures',
        'IIS-DefaultDocument',
        'IIS-ASPNET45',
        'IIS-ManagementConsole',
        'MSMQ-Server',
        'MSMQ-DCOMProxy',
        'WCF-HTTP-Activation45',
        'WCF-MSMQ-Activation45'
    )

    $restartNeeded = $false
    foreach ($feature in $features) {
        if (Enable-OptionalFeatureSafe -Name $feature -Source $source) {
            $restartNeeded = $true
        }
    }

    Write-Step 'OS: paths, firewall, discovery'
    Set-LongPaths
    Set-S7FirewallRules
    Enable-NetworkDiscovery

    Write-Step 'OS: power and network stability'
    if ($script:DryRun) {
        Write-Detail '[dry-run] activate High Performance power plan.'
    }
    else {
        Invoke-External -FilePath 'powercfg.exe' -ArgumentList @('/setactive', 'SCHEME_MIN') -AllowFailure | Out-Null
        Write-Ok 'High Performance power plan requested.'
    }

    Optimize-PlcAdapter -Name $script:PlcAdapter

    if ($restartNeeded -or (Test-RebootPending)) {
        if ($script:StackState) {
            $script:StackState.PendingReboot = $true
        }
        if ($restartNeeded) {
            Write-Warn 'Windows features changed. A reboot is required.'
        }
        else {
            Write-Warn 'A reboot is already pending from an earlier change.'
        }
    }
}
