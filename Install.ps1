#requires -Version 5.1
<#
.SYNOPSIS
    One entry point for the Windows stack.

.DESCRIPTION
    -Profile daily runs the modular engineering setup.
    -Profile iot runs the slim LTSC installer.
    Common switches are declared here. Other switches pass through unchanged.
    -Verify calls the matching validator. -Status is daily only.

.EXAMPLE
    .\Install.ps1 -Profile daily -DryRun
    .\Install.ps1 -Profile iot -DryRun
    .\Install.ps1 -Profile iot -ConfigsOnly
    .\Install.ps1 -Profile daily -Verify
    .\Install.ps1 -Profile daily -Status
#>
[CmdletBinding()]
param(
    [ValidateSet('daily', 'iot')][string]$Profile = 'daily',
    [switch]$DryRun,
    [switch]$Force,
    [string[]]$Only = @(),
    [switch]$Resume,
    [switch]$Verify,
    [switch]$Status,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$PassThru = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path

if ($Verify) {
    $entry = Join-Path $root 'Validate.ps1'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $entry -Profile $Profile
    if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    exit 0
}

if ($Status -and $Profile -ne 'daily') {
    throw '-Status is only available for the daily profile.'
}

if ($Profile -eq 'iot') {
    $entry = Join-Path $root 'install-Win-Iot.ps1'
}
else {
    $entry = Join-Path $root 'scripts\Install.ps1'
}

if (-not (Test-Path -LiteralPath $entry)) {
    throw "Missing profile entry point: $entry"
}

$arguments = @()
if ($DryRun) { $arguments += '-DryRun' }
if ($Force) { $arguments += '-Force' }
if ($Only.Count -gt 0) { $arguments += @('-Only', ($Only -join ',')) }
if ($Resume) { $arguments += '-Resume' }
if ($Status) { $arguments += '-Status' }
$arguments += $PassThru

& powershell -NoProfile -ExecutionPolicy Bypass -File $entry @arguments
if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
exit 0
