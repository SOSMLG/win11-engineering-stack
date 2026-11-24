# Shared single-pass debloat. Windows PowerShell 5.1 compatible.
# The list lives in config/debloat.json so the policy is reviewable.
# Nothing here touches Windows Update, Defender, Store, Terminal, WebView2, or .NET.

function Get-DebloatConfig {
    $path = Join-Path $script:ConfigRoot 'debloat.json'
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Debloat config missing: $path"
    }
    return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
}

function Set-DebloatDefaultRegistryValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [AllowEmptyString()][string]$Value = ''
    )

    $exists = Test-Path -LiteralPath $Path
    $current = $null
    if ($exists) {
        try { $current = (Get-Item -LiteralPath $Path).GetValue('') } catch { $current = $null }
    }
    if ($exists -and "$current" -eq "$Value") {
        Write-Skip "default value already set: $Path"
        return
    }

    if ($script:DryRun) {
        Write-Detail "[dry-run] default value $Path = '$Value'"
        return
    }

    try {
        if (-not $exists) {
            New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
        }
        Set-Item -LiteralPath $Path -Value $Value -ErrorAction Stop
        Write-Ok "default value set: $Path"
    }
    catch {
        Write-Skip "default value skipped: $Path ($($_.Exception.Message))"
    }
}

function Invoke-DebloatRegistry {
    param([object[]]$Items)

    foreach ($item in @($Items)) {
        if ($null -eq $item) { continue }
        try {
            Set-RegistryValue -Path $item.path -Name $item.name -Value $item.value -Type $item.type
        }
        catch {
            Write-Skip "registry value skipped: $($item.path)\$($item.name) ($($_.Exception.Message))"
        }
    }
}

function Invoke-DebloatAppx {
    param([string[]]$Names)

    if ($null -eq (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue)) {
        Write-Skip 'AppX cmdlets are missing; app removal skipped.'
        return
    }

    $provisionCmd = Get-Command Get-AppxProvisionedPackage -ErrorAction SilentlyContinue
    $removeProvisionCmd = Get-Command Remove-AppxProvisionedPackage -ErrorAction SilentlyContinue

    foreach ($name in @($Names)) {
        if (-not $name) { continue }

        $seen = $false
        $packages = @()
        try {
            $packages = @(Get-AppxPackage -Name $name -AllUsers -ErrorAction SilentlyContinue)
        }
        catch {
            $packages = @()
        }
        if (-not $packages.Count) {
            try {
                $packages = @(Get-AppxPackage -Name $name -ErrorAction SilentlyContinue)
            }
            catch {
                $packages = @()
            }
        }

        foreach ($package in $packages) {
            $seen = $true
            if ($script:DryRun) {
                Write-Detail "[dry-run] remove appx $($package.PackageFullName)"
                continue
            }

            $removed = $false
            try {
                Remove-AppxPackage -Package $package.PackageFullName -AllUsers -ErrorAction Stop
                $removed = $true
            }
            catch {
                try {
                    Remove-AppxPackage -Package $package.PackageFullName -ErrorAction Stop
                    $removed = $true
                }
                catch {
                    $removed = $false
                }
            }
            if ($removed) {
                Write-Ok "removed appx $name"
            }
            else {
                Write-Skip "appx $name is in use or locked"
            }
        }

        if ($provisionCmd -and $removeProvisionCmd) {
            $provisioned = @()
            try {
                $provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop |
                    Where-Object { $_.DisplayName -eq $name -or $_.PackageName -like "$name*" })
            }
            catch {
                $provisioned = @()
            }

            foreach ($package in $provisioned) {
                $seen = $true
                if ($script:DryRun) {
                    Write-Detail "[dry-run] remove provisioned appx $($package.PackageName)"
                    continue
                }
                try {
                    Remove-AppxProvisionedPackage -Online -PackageName $package.PackageName -ErrorAction Stop | Out-Null
                    Write-Ok "removed provisioned appx $name"
                }
                catch {
                    Write-Skip "provisioned appx $name could not be removed"
                }
            }
        }

        if (-not $seen) {
            Write-Skip "appx $name not present"
        }
    }
}

function Invoke-DebloatTasks {
    param([object[]]$Items)

    if ($null -eq (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue) -or
        $null -eq (Get-Command Disable-ScheduledTask -ErrorAction SilentlyContinue)) {
        Write-Skip 'Scheduled-task cmdlets are missing; task cleanup skipped.'
        return
    }

    foreach ($item in @($Items)) {
        if ($null -eq $item) { continue }
        $task = $null
        try {
            $task = Get-ScheduledTask -TaskPath $item.path -TaskName $item.name -ErrorAction SilentlyContinue
        }
        catch {
            $task = $null
        }
        if ($null -eq $task) {
            Write-Skip "task not present: $($item.name)"
            continue
        }
        if ($task.State -eq 'Disabled') {
            Write-Skip "task already disabled: $($item.name)"
            continue
        }
        if ($script:DryRun) {
            Write-Detail "[dry-run] disable task $($item.path)$($item.name)"
            continue
        }
        try {
            Disable-ScheduledTask -TaskPath $item.path -TaskName $item.name -ErrorAction Stop | Out-Null
            Write-Ok "disabled task $($item.name)"
        }
        catch {
            Write-Skip "task $($item.name) could not be disabled"
        }
    }
}

function Invoke-Debloat {
    param([switch]$Skip)

    if ($Skip) {
        Write-Skip 'Debloat skipped (-NoDebloat).'
        return
    }

    Write-Step 'Debloat: one default set'
    $config = Get-DebloatConfig

    Invoke-DebloatRegistry -Items @($config.registry)
    foreach ($item in @($config.defaultRegistryValues)) {
        if ($null -eq $item) { continue }
        Set-DebloatDefaultRegistryValue -Path $item.path -Value $item.value
    }
    Invoke-DebloatAppx -Names @($config.appx)
    Invoke-DebloatTasks -Items @($config.scheduledTasks)

    Write-Detail 'Kept: Windows Update, Defender, Store, Terminal, WebView2, .NET, Paint, Notepad, Photos, Camera, Snipping Tool, Sound Recorder, Media Player, QuickAssist.'
}
