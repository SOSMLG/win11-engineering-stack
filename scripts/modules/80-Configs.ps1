function Set-VSCodiumConfig {
    $source = Join-Path $script:ConfigRoot 'vscodium\settings.json'
    if (-not (Test-Path $source)) {
        Write-Warn "VSCodium settings template missing: $source"
        return
    }

    $settings = ConvertTo-DeepHashtable (Get-Content $source -Raw | ConvertFrom-Json)

    if (-not (Get-CommandPath 'python')) {
        $py = Get-CommandPath 'py'
        if ($py) {
            $interpreter = (& py -3 -c "import sys; print(sys.executable)" 2>$null) -join ''
            if ($interpreter -and (Test-Path $interpreter)) {
                $settings['python.defaultInterpreterPath'] = $interpreter -replace '\\', '/'
                Write-Detail "Python interpreter: $interpreter"
            }
        }
    }

    $target = Join-Path $env:APPDATA 'VSCodium\User\settings.json'
    Write-JsonFile -Path $target -Value $settings
    if ($script:DryRun) { Write-Detail "[dry-run] VSCodium settings would be merged: $target" }
    else { Write-Ok "VSCodium settings merged: $target" }
}

function Set-LibreWolfConfig {
    $source = Join-Path $script:RepoRoot 'LibreWolf\librewolf.overrides.cfg'
    if (-not (Test-Path $source)) {
        Write-Warn "LibreWolf overrides template missing: $source"
        return
    }

    $target = Join-Path $env:USERPROFILE '.librewolf\librewolf.overrides.cfg'
    if (Test-Path $target) {
        Write-Skip "LibreWolf overrides kept: $target"
        return
    }
    if ($script:DryRun) {
        Write-Detail "[dry-run] LibreWolf overrides would be written: $target"
        return
    }

    New-Item -ItemType Directory -Path (Split-Path $target) -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $target -Force
    Write-Ok "LibreWolf overrides written: $target"
}

function Set-OpenCodeConfig {
    $source = Join-Path $script:ConfigRoot 'opencode\opencode.json'
    if (-not (Test-Path $source)) {
        Write-Warn "OpenCode config template missing: $source"
        return
    }

    $targetDir = Join-Path $env:USERPROFILE '.config\opencode'
    $target = Join-Path $targetDir 'opencode.json'
    $agentsPath = Join-Path $targetDir 'AGENTS.md'

    $config = ConvertTo-DeepHashtable (Get-Content $source -Raw | ConvertFrom-Json)

    $existingV2 = $false
    if (Test-Path $target) {
        try {
            $existing = ConvertTo-DeepHashtable (Get-Content $target -Raw | ConvertFrom-Json)
            $existingV2 = $existing.ContainsKey('providers')
        }
        catch {
            $existingV2 = $false
        }
    }

    if ($existingV2 -and -not $script:Force) {
        Write-JsonFile -Path $target -Value $config
        if ($script:DryRun) { Write-Detail "[dry-run] OpenCode config would be merged (V2 provider shape): $target" }
        else { Write-Ok "OpenCode config merged (V2 provider shape): $target" }
    }
    else {
        Write-JsonFile -Path $target -Value $config -NoMerge
        if ($script:DryRun) { Write-Detail "[dry-run] OpenCode config would be replaced with the V2 provider shape: $target" }
        else { Write-Ok "OpenCode config replaced with the V2 provider shape: $target" }
    }

    $agentsSource = Join-Path $script:ConfigRoot 'opencode\AGENTS.md'
    if (Test-Path $agentsSource) {
        $agents = Get-Content $agentsSource -Raw
        Set-ManagedBlock `
            -Path $agentsPath `
            -Begin '<!-- win11-stack:begin -->' `
            -End '<!-- win11-stack:end -->' `
            -Content $agents
    }

    Write-Detail 'Restart OpenCode after this change. The old provider block is in the backup folder.'
}

function Set-VesktopConfig {
    $vesktopSource = Join-Path $script:ConfigRoot 'vesktop\settings.json'
    if (Test-Path $vesktopSource) {
        $vesktopTarget = Join-Path $env:APPDATA 'vesktop\settings.json'
        $vesktop = ConvertTo-DeepHashtable (Get-Content $vesktopSource -Raw | ConvertFrom-Json)
        Write-JsonFile -Path $vesktopTarget -Value $vesktop
        if ($script:DryRun) { Write-Detail "[dry-run] Vesktop settings would be merged: $vesktopTarget" }
        else { Write-Ok "Vesktop settings merged: $vesktopTarget" }
    }

    $vencordSource = Join-Path $script:ConfigRoot 'vencord\settings.json'
    if (Test-Path $vencordSource) {
        $vencordTarget = Join-Path $env:APPDATA 'vesktop\settings\settings.json'
        $vencord = ConvertTo-DeepHashtable (Get-Content $vencordSource -Raw | ConvertFrom-Json)
        Write-JsonFile -Path $vencordTarget -Value $vencord
        if ($script:DryRun) { Write-Detail "[dry-run] Vencord settings would be merged: $vencordTarget" }
        else { Write-Ok "Vencord settings merged: $vencordTarget" }
    }

    Write-Detail 'Close Vesktop before changing these files; it rewrites them on exit.'
}

function Invoke-Configs {
    Write-Step 'Configs: editor, OpenCode, Vesktop, LibreWolf'

    Set-VSCodiumConfig
    Set-OpenCodeConfig
    Set-VesktopConfig
    Set-LibreWolfConfig

    Write-Detail 'Config backups:'
    if ($script:BackupSession) {
        Write-Detail $script:BackupSession
    }
    else {
        Write-Detail (Join-Path $script:BackupRoot '<timestamp>')
    }
}
