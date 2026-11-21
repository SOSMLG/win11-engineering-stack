#requires -Version 5.1
<#
.SYNOPSIS
    Read-only validation for the engineering workstation setup.

.DESCRIPTION
    Prints PASS/FAIL/SKIP for image guardrails, Windows features, Defender,
    firewall, apps, Git, OmniRoute, OpenCode, theme, and fonts.
    Exits nonzero when a real check fails.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib\Common.ps1')

$script:DryRun = $false
$script:Force = $false

Get-ChildItem -Path (Join-Path $PSScriptRoot 'modules') -Filter '*.ps1' |
    Sort-Object Name |
    ForEach-Object { . $_.FullName }

Invoke-Validate

if ($script:ValidationFailed) { exit 1 }
exit 0
