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
    Write-Ok "VSCodium settings merged: $target"
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
        Write-Ok "OpenCode config merged (V2 provider shape): $target"
    }
    else {
        Write-JsonFile -Path $target -Value $config -NoMerge
        Write-Ok "OpenCode config replaced with the V2 provider shape: $target"
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
        Write-Ok "Vesktop settings merged: $vesktopTarget"
    }

    $vencordSource = Join-Path $script:ConfigRoot 'vencord\settings.json'
    if (Test-Path $vencordSource) {
        $vencordTarget = Join-Path $env:APPDATA 'vesktop\settings\settings.json'
        $vencord = ConvertTo-DeepHashtable (Get-Content $vencordSource -Raw | ConvertFrom-Json)
        Write-JsonFile -Path $vencordTarget -Value $vencord
        Write-Ok "Vencord settings merged: $vencordTarget"
    }

    Write-Detail 'Close Vesktop before changing these files; it rewrites them on exit.'
}

function Invoke-Configs {
    Write-Step 'Configs: editor, OpenCode, Vesktop'

    Set-VSCodiumConfig
    Set-OpenCodeConfig
    Set-VesktopConfig

    Write-Detail 'Config backups:'
    if ($script:BackupSession) {
        Write-Detail $script:BackupSession
    }
    else {
        Write-Detail (Join-Path $script:BackupRoot '<timestamp>')
    }
}
