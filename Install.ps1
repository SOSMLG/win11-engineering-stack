#requires -Version 5.1
<#
.SYNOPSIS
    One entry point for the Windows stack.

.DESCRIPTION
    -Profile daily runs the modular engineering setup.
    -Profile iot runs the slim LTSC installer.
    Extra switches pass through to that profile unchanged.

.EXAMPLE
    .\Install.ps1 -Profile daily -DryRun
    .\Install.ps1 -Profile iot -DryRun
    .\Install.ps1 -Profile iot -ConfigsOnly
#>
[CmdletBinding()]
param(
    [ValidateSet('daily', 'iot')][string]$Profile = 'daily',
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$PassThru = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
if ($Profile -eq 'iot') {
    $entry = Join-Path $root 'install-Win-Iot.ps1'
}
else {
    $entry = Join-Path $root 'scripts\Install.ps1'
}

if (-not (Test-Path -LiteralPath $entry)) {
    throw "Missing profile entry point: $entry"
}

& powershell -NoProfile -ExecutionPolicy Bypass -File $entry @PassThru
if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
exit 0
