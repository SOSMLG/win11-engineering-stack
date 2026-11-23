#requires -Version 5.1
<#
.SYNOPSIS
    Read-only validation for the selected profile.

.DESCRIPTION
    -Profile daily calls scripts/Validate.ps1 and is the default.
    -Profile iot calls scripts/Install.ps1 -Profile iot -Verify.
    Neither path writes settings.
#>
[CmdletBinding()]
param(
    [ValidateSet('daily', 'iot')][string]$Profile = 'daily'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
if ($Profile -eq 'iot') {
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'scripts\Install.ps1') -Profile iot -Verify
}
else {
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'scripts\Validate.ps1')
}

if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
exit 0
