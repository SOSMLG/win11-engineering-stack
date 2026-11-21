function Get-MatlabRoot {
    $base = 'C:\Program Files\MATLAB'
    if (-not (Test-Path $base)) { return $null }
    $candidate = Get-ChildItem -Path $base -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-Path (Join-Path $_.FullName 'bin\matlab.exe') } |
        Sort-Object Name -Descending |
        Select-Object -First 1
    if ($candidate) { return $candidate.FullName }
    return $null
}

function Get-TiaRoot {
    $base = 'C:\Program Files\Siemens\Automation'
    if (-not (Test-Path $base)) { return $null }
    $candidate = Get-ChildItem -Path $base -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^Portal' } |
        Sort-Object Name -Descending |
        Select-Object -First 1
    if ($candidate) { return $candidate.FullName }
    return $null
}

function Set-MachinePathEntry {
    param(
        [Parameter(Mandatory = $true)][string]$Entry,
        [ValidateSet('Machine', 'User')][string]$Scope = 'Machine'
    )

    $current = [Environment]::GetEnvironmentVariable('Path', $Scope)
    if ($null -eq $current) { $current = '' }
    $parts = @($current -split ';' | Where-Object { $_ })
    if ($parts -contains $Entry) {
        Write-Skip "PATH already contains $Entry"
        return
    }

    if ($script:DryRun) {
        Write-Detail "[dry-run] add to $Scope PATH: $Entry"
        return
    }
    $updated = (($parts + $Entry) -join ';')
    [Environment]::SetEnvironmentVariable('Path', $updated, $Scope)
    Write-Ok "added to $Scope PATH: $Entry"
}

function Install-EngineeringExclusions {
    $paths = @(
        'C:\Program Files\Siemens',
        'C:\ProgramData\Siemens',
        'C:\Program Files\MATLAB',
        (Join-Path $env:USERPROFILE 'Documents\MATLAB'),
        (Join-Path $env:USERPROFILE 'Documents\Engineering')
    )

    if ($env:WIN11STACK_EXCLUSIONS) {
        foreach ($extra in ($env:WIN11STACK_EXCLUSIONS -split ';')) {
            $trimmed = $extra.Trim()
            if ($trimmed) { $paths += $trimmed }
        }
    }

    $existing = @($paths | Where-Object { Test-Path $_ } | Select-Object -Unique)
    if ($existing.Count -eq 0) {
        Write-Skip 'No engineering folders exist yet; exclusions not added.'
        return
    }

    Add-DefenderExclusion -Path $existing
}

function Set-DefenderTuning {
    if ($null -eq (Get-Command Add-MpPreference -ErrorAction SilentlyContinue)) {
        Write-Skip 'Defender cmdlets are not available; tuning skipped.'
        return
    }

    $prefs = Get-MpPreference
    Write-Detail "Defender sample submission: $(Get-PropValue $prefs 'SubmitSamplesConsent' 'current')"
    Write-Detail "Defender cloud reporting: $(Get-PropValue $prefs 'MAPSReporting' 'current')"
    Write-Detail 'Defender scan schedule and reporting stay at their current values.'
    Write-Detail 'Only Add-MpPreference is used, for exclusions. Real-time protection stays on.'
}

function Install-MatlabEnvironment {
    $root = Get-MatlabRoot
    if (-not $root) {
        Write-Skip 'MATLAB is not installed; environment setup skipped.'
        return
    }

    Write-Detail "MATLAB root: $root"
    if ($script:DryRun) {
        Write-Detail "[dry-run] set MATLABROOT=$root"
    }
    else {
        [Environment]::SetEnvironmentVariable('MATLABROOT', $root, 'Machine')
        Write-Ok "MATLABROOT=$root"
    }

    Set-MachinePathEntry -Entry (Join-Path $root 'bin') -Scope Machine
}

function Start-SuppliedInstaller {
    param(
        [string]$Path,
        [string]$Name
    )

    if (-not $Path) {
        Write-Skip "No $Name installer supplied."
        return
    }

    if (-not (Test-Path $Path)) {
        Write-Warn "$Name installer not found: $Path"
        return
    }

    $target = $Path
    if ((Get-Item $Path).PSIsContainer) {
        $candidates = @('Start.exe', 'setup.exe', 'install.exe')
        $found = $null
        foreach ($candidate in $candidates) {
            $probe = Join-Path $Path $candidate
            if (Test-Path $probe) { $found = $probe; break }
        }
        if (-not $found) {
            Write-Warn "$Name folder has no Start.exe or setup.exe: $Path"
            return
        }
        $target = $found
    }

    if ($script:DryRun) {
        Write-Detail "[dry-run] start $Name installer: $target"
        return
    }

    Write-Detail "Starting $Name installer: $target"
    Start-Process -FilePath $target -WorkingDirectory (Split-Path -Parent $target)
    Write-Ok "$Name installer started. Finish it, then rerun: .\scripts\Install.ps1 -Only engineering"
}

function Invoke-Engineering {
    Write-Step 'Engineering: workspaces, exclusions, MATLAB, installers'
    Assert-Admin

    $workspace = Join-Path $env:USERPROFILE 'Documents\Engineering'
    $folders = @(
        $workspace,
        (Join-Path $workspace 'PLC'),
        (Join-Path $workspace 'MATLAB'),
        (Join-Path $workspace 'Python'),
        (Join-Path $workspace 'datasets')
    )

    foreach ($folder in $folders) {
        if (Test-Path $folder) {
            Write-Skip "folder exists: $folder"
            continue
        }
        if ($script:DryRun) {
            Write-Detail "[dry-run] create $folder"
            continue
        }
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        Write-Ok "created $folder"
    }

    Install-EngineeringExclusions
    Set-DefenderTuning
    Install-MatlabEnvironment

    $tia = Get-TiaRoot
    if ($tia) {
        Write-Skip "TIA Portal already installed: $tia"
        Write-Detail 'Set the PG/PC interface to the physical PLC adapter after connecting hardware.'
    }
    else {
        Start-SuppliedInstaller -Path $script:TiaInstaller -Name 'TIA Portal'
    }

    if (Get-MatlabRoot) {
        Write-Skip 'MATLAB already installed.'
    }
    else {
        Start-SuppliedInstaller -Path $script:MatlabInstaller -Name 'MATLAB'
    }

    Write-Detail 'S7 uses TCP 102; PROFINET DCP/RT is Layer 2 and bypasses Windows Firewall.'
}
