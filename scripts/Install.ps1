#requires -Version 5.1
<#
.SYNOPSIS
    Installs and configures a Windows 11 engineering workstation.

.DESCRIPTION
    Modular, idempotent setup for TIA Portal prerequisites, MATLAB paths,
    VSCodium, Git/gh, developer tools, OmniRoute, and OpenCode.

.PARAMETER Status
    Print saved module state and the next command. Reads state only.

.PARAMETER DryRun
    Print every action without changing files, registry, services, or packages.

.PARAMETER Only
    Run selected modules: all, preflight, os, packages, apps, engineering,
    developer, omniroute, theme, configs, validate.

.PARAMETER Resume
    Continue after the reboot requested by the OS module.

.PARAMETER Force
    Overwrite configs instead of merging and rerun completed modules.

.PARAMETER SxsPath
    Path to the ISO sources\sxs folder, used when .NET 3.5 payload is missing.

.PARAMETER GitName
    Git user.name to set when it is missing.

.PARAMETER GitEmail
    Git user.email to set when it is missing.

.PARAMETER TiaInstaller
    Path to TIA Portal Start.exe or its folder.

.PARAMETER MatlabInstaller
    Path to MATLAB setup.exe or its folder.
#>
[CmdletBinding()]
param(
    [ValidateSet('daily', 'iot')][string]$Profile = 'daily',
    [switch]$Status,
    [switch]$DryRun,
    [string[]]$Only = @(),
    [switch]$Resume,
    [switch]$Force,
    [string]$SxsPath,
    [string]$GitName,
    [string]$GitEmail,
    [string]$TiaInstaller,
    [string]$MatlabInstaller,
    [string]$StateDir = 'C:\Windows\Logs\Win-Iot-Setup\state',
    [string]$BuildConfig = '',
    [string]$Arch = '',
    [switch]$DetectHardware,
    [switch]$Minimal,
    [switch]$Unattended,
    [switch]$NoWingetBootstrap,
    [string]$OfflineDir = '',
    [string]$LogDir = 'C:\Windows\Logs\Win-Iot-Setup',
    [string]$DriverDir = '',
    [switch]$ConfigsOnly,
    [switch]$Reboot,
    [switch]$Fixes,
    [switch]$Verify,
    [switch]$SkipHashVerify,
    [switch]$Idempotent,
    [string[]]$SkipApps = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$libPath = Join-Path $PSScriptRoot 'lib\Common.ps1'
. $libPath

if ($Profile -eq 'iot') {
    # IoT profile: run the modular IoT implementation from scripts/modules/iot.
    . (Join-Path $PSScriptRoot 'modules\iot\IotMain.ps1')
    exit 0
}

if ($Status) {
    $statusState = Get-StackState
    $statusOrder = @('preflight', 'os', 'packages', 'apps', 'engineering', 'developer', 'omniroute', 'theme', 'configs', 'validate')
    $statusDone = @($statusState.Completed)
    $statusTodo = @($statusOrder | Where-Object { $statusDone -notcontains $_ })
    Write-Host 'win11-engineering-stack status'
    Write-Host "  state:  $script:StatePath"
    Write-Host "  last:   $(if ($statusState.LastRun) { $statusState.LastRun } else { 'never' })"
    Write-Host "  reboot: $($statusState.PendingReboot)"
    Write-Host "  done:   $(if ($statusDone.Count) { $statusDone -join ', ' } else { 'none' })"
    Write-Host "  todo:   $(if ($statusTodo.Count) { $statusTodo -join ', ' } else { 'none' })"
    if ($statusState.PendingReboot) {
        Write-Host '  next:   reboot, then .\Install.ps1 -Resume'
    }
    else {
        Write-Host '  next:   .\Validate.ps1 -Profile daily'
    }
    return
}

Reset-WriteCounts
$script:DryRun = [bool]$DryRun
$script:Force = [bool]$Force
$script:SxsPath = $SxsPath
$script:GitName = $GitName
$script:GitEmail = $GitEmail
$script:TiaInstaller = $TiaInstaller
$script:MatlabInstaller = $MatlabInstaller

# -File passes "apps,engineering" as one string; accept both forms.
$Only = @($Only | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })

if (-not (Test-Admin) -and -not $DryRun) {
    $adminModules = @('os', 'engineering', 'developer')
    $needsAdmin = ($Only.Count -eq 0) -or ($Only -contains 'all') -or (@($Only | Where-Object { $adminModules -contains $_ }).Count -gt 0)
}
else {
    $needsAdmin = $false
}

if ($needsAdmin) {
    Write-Host 'Elevation required. Relaunching with UAC...' -ForegroundColor Yellow

    $quote = {
        param([string]$Value)
        if ($Value -match '\s') { return '"' + $Value + '"' }
        return $Value
    }

    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (& $quote $PSCommandPath))
    if ($Only.Count -gt 0) { $arguments += @('-Only', (& $quote ($Only -join ','))) }
    if ($Resume) { $arguments += '-Resume' }
    if ($Force) { $arguments += '-Force' }
    if ($SxsPath) { $arguments += @('-SxsPath', (& $quote $SxsPath)) }
    if ($GitName) { $arguments += @('-GitName', (& $quote $GitName)) }
    if ($GitEmail) { $arguments += @('-GitEmail', (& $quote $GitEmail)) }
    if ($TiaInstaller) { $arguments += @('-TiaInstaller', (& $quote $TiaInstaller)) }
    if ($MatlabInstaller) { $arguments += @('-MatlabInstaller', (& $quote $MatlabInstaller)) }

    $hostExe = (Get-Process -Id $PID).Path
    $child = Start-Process -FilePath $hostExe -Verb RunAs -ArgumentList ($arguments -join ' ') -Wait -PassThru
    if ($null -ne $child.ExitCode) {
        exit $child.ExitCode
    }
    return
}

$order = @('preflight', 'os', 'packages', 'apps', 'engineering', 'developer', 'omniroute', 'theme', 'configs', 'validate')
$functions = @{
    preflight   = 'Invoke-Preflight'
    os          = 'Invoke-OS'
    packages    = 'Invoke-Packages'
    apps        = 'Invoke-Apps'
    engineering = 'Invoke-Engineering'
    developer   = 'Invoke-Developer'
    omniroute   = 'Invoke-OmniRoute'
    theme       = 'Invoke-Theme'
    configs     = 'Invoke-Configs'
    validate    = 'Invoke-Validate'
}

$selected = @()
if ($Only.Count -eq 0 -or $Only -contains 'all') {
    $selected = $order
}
else {
    foreach ($name in $Only) {
        if ($order -notcontains $name) {
            throw "Unknown module '$name'. Valid values: all, $($order -join ', ')."
        }
        $selected += $name
    }
}

$selected = @($selected | Select-Object -Unique)

$moduleRoot = Join-Path $PSScriptRoot 'modules'
Get-ChildItem -Path $moduleRoot -Filter '*.ps1' -File | Sort-Object Name | ForEach-Object {
    . $_.FullName
}

$state = Get-StackState
$script:StackState = $state
$fullRun = ($selected.Count -eq $order.Count)
$startedAt = Get-Date
$failed = $false
$transcript = $null

if (-not $DryRun) {
    if (-not (Test-Path $script:LogRoot)) {
        New-Item -ItemType Directory -Path $script:LogRoot -Force | Out-Null
    }
    $transcript = Join-Path $script:LogRoot ("install-{0}.log" -f (Get-Timestamp))
    try {
        Start-Transcript -Path $transcript | Out-Null
    }
    catch {
        Write-Warn "Could not start transcript: $($_.Exception.Message)"
        $transcript = $null
    }
}

Write-Host ''
Write-Host 'win11-engineering-stack' -ForegroundColor White
Write-Host "  repo:  $script:RepoRoot"
Write-Host "  mode:  $(if ($DryRun) { 'dry run' } else { 'apply' })"
Write-Host "  only:  $($selected -join ', ')"
if ($transcript) { Write-Host "  log:   $transcript" }

if ($state.PendingReboot -and -not $Resume -and $fullRun) {
    Write-Warn 'A previous run is waiting for a reboot.'
    Write-Warn 'Reboot, then run: .\scripts\Install.ps1 -Resume'
    if ($transcript) { Stop-Transcript | Out-Null }
    return
}

if ($Resume) {
    $state.PendingReboot = $false
    Save-StackState $state
}

try {
    foreach ($name in $selected) {
        if ($Resume -and -not $Force -and $state.Completed -contains $name -and $name -ne 'preflight') {
            Write-Skip "module '$name' already completed."
            continue
        }

        $functionName = $functions[$name]
        if ($null -eq (Get-Command $functionName -ErrorAction SilentlyContinue)) {
            throw "Module function $functionName is missing. Check scripts\modules."
        }

        $script:ModuleFailed = $false
        & $functionName

        if ($script:ModuleFailed) {
            $failed = $true
            Write-Fail "module '$name' reported failure."
        }
        elseif (-not $DryRun) {
            if ($state.Completed -notcontains $name) {
                $state.Completed += $name
            }
            Save-StackState $state
        }

        if ($state.PendingReboot -and -not $DryRun) {
            Write-Host ''
            Write-Warn 'A reboot is required before continuing.'
            Write-Warn 'Reboot, then run: .\scripts\Install.ps1 -Resume'
            break
        }
    }

    $validation = Get-Variable -Name ValidationFailed -Scope Script -ErrorAction SilentlyContinue
    if ($validation -and $validation.Value) {
        $failed = $true
    }
}
catch {
    $failed = $true
    Write-Fail $_.Exception.Message
    if ($_.ScriptStackTrace) {
        Write-Detail $_.ScriptStackTrace
    }
}
finally {
    $elapsed = (Get-Date) - $startedAt
    Write-Host ''
    Write-Host ("Finished in {0:mm\:ss}" -f $elapsed) -ForegroundColor White
    Write-WriteSummary
    if ($state.PendingReboot -and -not $DryRun) {
        Write-Host '  next:   .\Install.ps1 -Resume' -ForegroundColor Yellow
    }
    else {
        Write-Host '  next:   .\Validate.ps1 -Profile daily' -ForegroundColor Yellow
    }
    if ($transcript) { Stop-Transcript | Out-Null }
}

if ($failed) { exit 1 }
exit 0
