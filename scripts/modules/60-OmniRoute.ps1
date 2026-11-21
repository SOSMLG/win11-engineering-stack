function Test-OmniRoute {
    try {
        $response = Invoke-WebRequest -Uri 'http://127.0.0.1:20128/v1/models' -UseBasicParsing -TimeoutSec 3
        return ($response.StatusCode -eq 200)
    }
    catch {
        $status = $null
        $response = Get-PropValue $_.Exception 'Response' $null
        if ($null -ne $response) {
            $status = [int](Get-PropValue $response 'StatusCode' 0)
        }
        return ($status -eq 401 -or $status -eq 403)
    }
}

function Register-OmniRouteTask {
    param([Parameter(Mandatory = $true)][string]$CommandPath)

    $taskName = 'OmniRoute'
    $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Skip "scheduled task '$taskName' already exists."
        return
    }

    $binRoot = Join-Path $env:LOCALAPPDATA 'win11-stack\bin'
    $wrapper = Join-Path $binRoot 'omniroute-serve.cmd'
    $wrapperBody = '@echo off' + [Environment]::NewLine +
        'call "' + $CommandPath + '" serve --no-open' + [Environment]::NewLine
    $actionText = "$env:ComSpec /c ""$wrapper"""

    if ($script:DryRun) {
        Write-Detail "[dry-run] write logon wrapper: $wrapper"
        Write-Detail "[dry-run] register logon task '$taskName': $actionText"
        return
    }

    try {
        if (-not (Test-Path $binRoot)) {
            New-Item -ItemType Directory -Path $binRoot -Force | Out-Null
        }
        Set-Content -LiteralPath $wrapper -Value $wrapperBody -Encoding Default -Force
        $action = New-ScheduledTaskAction -Execute $env:ComSpec -Argument ('/c "' + $wrapper + '"') -WorkingDirectory $env:USERPROFILE
        $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero)
        $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description 'Starts the local OmniRoute gateway at logon.' | Out-Null
        Write-Ok "scheduled task '$taskName' registered."
        Write-Detail "logon wrapper: $wrapper"
    }
    catch {
        Write-Warn "Could not register the logon task: $($_.Exception.Message)"
        Write-Detail "Create it manually: $CommandPath serve --no-open"
    }
}

function Set-OmniRouteNetwork {
    $hostValue = [Environment]::GetEnvironmentVariable('OMNIROUTE_SERVER_HOST', 'User')
    if ($hostValue -ne '127.0.0.1') {
        if ($script:DryRun) {
            Write-Detail '[dry-run] set user OMNIROUTE_SERVER_HOST=127.0.0.1'
        }
        else {
            [Environment]::SetEnvironmentVariable('OMNIROUTE_SERVER_HOST', '127.0.0.1', 'User')
            Write-Ok 'OmniRoute will bind to 127.0.0.1 on the next start.'
        }
    }
    else {
        Write-Skip 'OmniRoute host already 127.0.0.1.'
    }
    $env:OMNIROUTE_SERVER_HOST = '127.0.0.1'

    # Key is read from the environment only. Never write it to a file.
    if ($env:OMNIROUTE_API_KEY) {
        $requireKey = [Environment]::GetEnvironmentVariable('REQUIRE_API_KEY', 'User')
        if ($requireKey -ne 'true') {
            if ($script:DryRun) {
                Write-Detail '[dry-run] set user REQUIRE_API_KEY=true'
            }
            else {
                [Environment]::SetEnvironmentVariable('REQUIRE_API_KEY', 'true', 'User')
                Write-Ok 'OmniRoute inference plane requires the API key.'
            }
        }
        else {
            Write-Skip 'OmniRoute already requires the API key.'
        }
        $env:REQUIRE_API_KEY = 'true'
    }
    else {
        Write-Warn 'OMNIROUTE_API_KEY is unset; leaving the API-key requirement unchanged.'
    }
}

function Test-OmniRouteLoopback {
    $listeners = @(Get-NetTCPConnection -LocalPort 20128 -State Listen -ErrorAction SilentlyContinue)
    if ($listeners.Count -eq 0) { return $true }
    $public = @($listeners | Where-Object { $_.LocalAddress -notin @('127.0.0.1', '::1') })
    return ($public.Count -eq 0)
}

function Invoke-OmniRoute {
    Write-Step 'OmniRoute: local gateway'

    Set-OmniRouteNetwork

    $node = Get-CommandPath 'node'
    $npm = Get-CommandPath 'npm'
    if (-not $node -or -not $npm) {
        Write-Fail 'Node.js and npm are required for OmniRoute.'
        return
    }
    Write-Detail "node: $((& node --version 2>$null) -join '')"

    $cli = Get-CommandPath 'omniroute.cmd'
    if (-not $cli) { $cli = Get-CommandPath 'omniroute' }
    if (-not $cli) {
        Write-Detail 'OmniRoute CLI not found; installing.'
        if ($script:DryRun) {
            Write-Detail '[dry-run] npm install -g omniroute'
        }
        else {
            $code = Invoke-External -FilePath 'npm' -ArgumentList @('install', '-g', 'omniroute') -AllowFailure
            if ($code -ne 0) {
                Write-Fail 'OmniRoute installation failed.'
                return
            }
            $cli = Get-CommandPath 'omniroute.cmd'
            if (-not $cli) { $cli = Get-CommandPath 'omniroute' }
        }
    }

    if ($cli) {
        $version = (& $cli --version 2>$null) -join ''
        Write-Detail "omniroute: $version"
    }

    if (-not $env:OMNIROUTE_API_KEY) {
        Write-Warn 'OMNIROUTE_API_KEY is not set in this session.'
        Write-Detail 'Open the dashboard once, copy the key, and set it as a user environment variable.'
    }

    if ((Test-OmniRoute) -and (Test-OmniRouteLoopback)) {
        Write-Skip 'OmniRoute is already responding on 127.0.0.1:20128.'
    }
    elseif ($script:DryRun) {
        if (Test-OmniRoute) {
            Write-Detail '[dry-run] restart OmniRoute so it binds to 127.0.0.1.'
        }
        else {
            Write-Detail '[dry-run] omniroute serve --daemon --no-open'
        }
    }
    else {
        if (Test-OmniRoute) {
            Write-Detail 'restarting OmniRoute to apply the loopback binding.'
            Invoke-External -FilePath $cli -ArgumentList @('stop') -AllowFailure | Out-Null
            Start-Sleep -Seconds 1
        }

        if ($cli -match '\.(cmd|exe)$') {
            # A hidden console keeps the detached daemon from inheriting our stdout pipe.
            try {
                $serve = Start-Process -FilePath $cli -ArgumentList @('serve', '--daemon', '--no-open') `
                    -WindowStyle Hidden -PassThru
                $null = $serve.WaitForExit(30000)
            }
            catch {
                Write-Warn "Could not start OmniRoute: $($_.Exception.Message)"
            }
        }
        else {
            Invoke-External -FilePath $cli -ArgumentList @('serve', '--daemon', '--no-open') -AllowFailure | Out-Null
        }

        $ready = $false
        for ($attempt = 1; $attempt -le 20; $attempt++) {
            Start-Sleep -Seconds 2
            if (Test-OmniRoute) {
                $ready = $true
                break
            }
        }

        if ($ready) {
            Write-Ok 'OmniRoute is responding on 127.0.0.1:20128.'
        }
        else {
            Write-Warn 'OmniRoute did not become ready. Check the logs:'
            Write-Detail (Join-Path $env:USERPROFILE '.omniroute\logs')
            Write-Detail 'Start it manually: omniroute serve --no-open'
        }
    }

    if ($cli -and $cli -match '\.(cmd|exe)$') {
        Register-OmniRouteTask -CommandPath $cli
    }
    elseif ($cli) {
        Write-Warn "OmniRoute CLI is a script ($cli); create the logon task manually."
    }

    Write-Detail 'Dashboard: http://127.0.0.1:20128/dashboard'
    Write-Detail 'OpenCode provider base URL: http://127.0.0.1:20128/v1'
}
