# Shared helpers. Windows PowerShell 5.1 compatible.
Set-StrictMode -Version Latest

$script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:ConfigRoot = Join-Path $script:RepoRoot 'config'
$script:StateRoot = Join-Path $env:LOCALAPPDATA 'win11-stack'
$script:LogRoot = Join-Path $script:StateRoot 'logs'
$script:BackupRoot = Join-Path $script:StateRoot 'backups'
$script:StatePath = Join-Path $script:StateRoot 'state.json'
if (-not (Get-Variable -Name DryRun -Scope Script -ErrorAction SilentlyContinue)) {
    $script:DryRun = $false
}
if (-not (Get-Variable -Name Force -Scope Script -ErrorAction SilentlyContinue)) {
    $script:Force = $false
}
$script:BackupSession = $null
$script:BackedUp = @{}
$script:CountOk = 0
$script:CountSkip = 0
$script:CountWarn = 0
$script:CountFail = 0
$script:ModuleFailed = $false

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "== $Message" -ForegroundColor Cyan
}

function Write-Detail {
    param([string]$Message)
    Write-Host "   $Message" -ForegroundColor Gray
}

function Write-Ok {
    param([string]$Message)
    $script:CountOk = $script:CountOk + 1
    Write-Host "   [ok] $Message" -ForegroundColor Green
}

function Write-Skip {
    param([string]$Message)
    $script:CountSkip = $script:CountSkip + 1
    Write-Host "   [skip] $Message" -ForegroundColor Yellow
}

function Write-Warn {
    param([string]$Message)
    $script:CountWarn = $script:CountWarn + 1
    Write-Host "   [warn] $Message" -ForegroundColor Yellow
}

function Write-Fail {
    param([string]$Message)
    $script:CountFail = $script:CountFail + 1
    Write-Host "   [fail] $Message" -ForegroundColor Red
}

function Reset-WriteCounts {
    $script:CountOk = 0
    $script:CountSkip = 0
    $script:CountWarn = 0
    $script:CountFail = 0
    $script:ModuleFailed = $false
}

function Write-WriteSummary {
    Write-Host ("summary: ok {0}, skip {1}, warn {2}, fail {3}" -f $script:CountOk, $script:CountSkip, $script:CountWarn, $script:CountFail) -ForegroundColor White
}

function Set-ModuleFailed {
    $script:ModuleFailed = $true
}

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-Admin {
    if (-not (Test-Admin) -and -not $script:DryRun) {
        throw 'This step needs an elevated PowerShell. Run Install.ps1 again and accept the UAC prompt.'
    }
}

function Get-CommandPath {
    param([string]$Name)
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($null -eq $cmd) { return $null }
    return $cmd.Source
}

function Get-Timestamp {
    return Get-Date -Format 'yyyyMMdd-HHmmss'
}

function Invoke-External {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [switch]$AllowFailure
    )

    $display = "$FilePath $($ArgumentList -join ' ')"
    if ($script:DryRun) {
        Write-Detail "[dry-run] $display"
        return 0
    }

    $global:LASTEXITCODE = 0
    & $FilePath @ArgumentList | Out-Host
    $code = $global:LASTEXITCODE
    if ($null -eq $code) { $code = 0 }
    if ($code -ne 0 -and -not $AllowFailure) {
        throw "Command failed with exit code $code`: $display"
    }
    return $code
}

function Get-PropValue {
    param(
        [object]$Object,
        [string]$Name,
        [object]$Default = $null
    )
    if ($null -eq $Object) { return $Default }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop) { return $Default }
    return $prop.Value
}

function Get-StackState {
    $state = @{
        Completed     = @()
        PendingReboot = $false
        LastRun       = $null
    }
    if (Test-Path $script:StatePath) {
        try {
            $raw = Get-Content $script:StatePath -Raw | ConvertFrom-Json
            $state.Completed = @(Get-PropValue $raw 'Completed' @() | Where-Object { $_ })
            $state.PendingReboot = [bool](Get-PropValue $raw 'PendingReboot' $false)
            $state.LastRun = Get-PropValue $raw 'LastRun' $null
        }
        catch {
            Write-Warn "Could not read state file; starting fresh."
        }
    }
    return $state
}

function Save-StackState {
    param([hashtable]$State)
    if ($script:DryRun) { return }
    if (-not (Test-Path $script:StateRoot)) {
        New-Item -ItemType Directory -Path $script:StateRoot -Force | Out-Null
    }
    $State.LastRun = (Get-Date).ToString('o')
    $json = ConvertTo-Json -InputObject $State -Depth 10
    Write-Utf8File -Path $script:StatePath -Content $json
}

function Test-RebootPending {
    $keys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    )
    foreach ($path in $keys) {
        if (Test-Path $path) { return $true }
    }

    $sessionManager = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
    $renames = Get-PropValue $sessionManager 'PendingFileRenameOperations' $null
    if ($null -ne $renames -and @($renames).Count -gt 0) { return $true }

    return $false
}

function Get-OptionalFeatureState {
    param([string]$Name)
    try {
        $feature = Get-WindowsOptionalFeature -Online -FeatureName $Name -ErrorAction Stop
        return $feature.State.ToString()
    }
    catch {
        return 'Unknown'
    }
}

function Get-ImageGuardrails {
    $defenderCmdlet = $null -ne (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue)
    $defenderService = $null -ne (Get-Service -Name WinDefend -ErrorAction SilentlyContinue)
    $winget = $null -ne (Get-CommandPath 'winget')
    if (-not $winget) {
        $alias = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
        $winget = Test-Path $alias
    }
    return [pscustomobject]@{
        DefenderCmdlet = $defenderCmdlet
        DefenderService = $defenderService
        WinSxS         = Test-Path (Join-Path $env:WINDIR 'WinSxS')
        Winget         = $winget
        ComponentStore = Test-Path (Join-Path $env:WINDIR 'WinSxS\Backup')
        Appx           = $null -ne (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue)
        ScheduledTasks = $null -ne (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue)
    }
}

function Get-TerminalSettingsPath {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
    )
    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) { return $candidate }
    }
    return $null
}

function Get-ConfigTargets {
    $targets = [ordered]@{
        vscodium       = Join-Path $env:APPDATA 'VSCodium\User\settings.json'
        opencodeConfig = Join-Path $env:USERPROFILE '.config\opencode\opencode.json'
        opencodeAgents = Join-Path $env:USERPROFILE '.config\opencode\AGENTS.md'
        profilePwsh    = Join-Path $env:USERPROFILE 'Documents\PowerShell\profile.ps1'
        profileWinPS   = Join-Path $env:USERPROFILE 'Documents\WindowsPowerShell\profile.ps1'
        vesktop        = Join-Path $env:APPDATA 'vesktop\settings.json'
        vencord        = Join-Path $env:APPDATA 'vesktop\settings\settings.json'
        gitconfig      = Join-Path $env:USERPROFILE '.gitconfig'
    }
    $terminal = Get-TerminalSettingsPath
    if ($terminal) { $targets['terminal'] = $terminal }
    return $targets
}

function Set-RegistryValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][object]$Value,
        [ValidateSet('String', 'DWord', 'QWord', 'ExpandString')][string]$Type = 'DWord'
    )

    $current = Get-PropValue (Get-ItemProperty -Path $Path -ErrorAction SilentlyContinue) $Name $null
    $alreadySet = $false
    if ($null -ne $current) {
        if ($Type -eq 'DWord') {
            try { $alreadySet = ([uint32]$current -eq [uint32]$Value) }
            catch { $alreadySet = $false }
        }
        else {
            $alreadySet = ("$current" -eq "$Value")
        }
    }
    if ($alreadySet) {
        Write-Skip "$Name already set at $Path"
        return
    }

    if ($script:DryRun) {
        Write-Detail "[dry-run] $Path\$Name = $Value"
        return
    }

    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
    Write-Ok "$Name = $Value"
}

function New-BackupSession {
    if ($script:DryRun) { return }
    if ($null -ne $script:BackupSession) { return }
    $script:BackupSession = Join-Path $script:BackupRoot (Get-Timestamp)
    New-Item -ItemType Directory -Path $script:BackupSession -Force | Out-Null
}

function Backup-File {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return }
    if ($script:BackedUp.ContainsKey($Path)) { return }

    $script:BackedUp[$Path] = $true
    if ($script:DryRun) {
        Write-Detail "[dry-run] back up $Path"
        return
    }

    New-BackupSession
    $hash = [BitConverter]::ToString(
        [Security.Cryptography.SHA1]::Create().ComputeHash(
            [Text.Encoding]::UTF8.GetBytes($Path)
        )
    ).Replace('-', '').Substring(0, 8).ToLowerInvariant()
    $leaf = Split-Path -Leaf $Path
    $destination = Join-Path $script:BackupSession "$hash-$leaf"
    Copy-Item -LiteralPath $Path -Destination $destination -Force
    Write-Detail "backup: $destination"
}

function Write-Utf8File {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content
    )
    if ($script:DryRun) {
        Write-Detail "[dry-run] write $Path"
        return
    }
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function ConvertTo-DeepHashtable {
    param([object]$InputObject)

    if ($null -eq $InputObject) { return $null }

    if ($InputObject -is [System.Collections.IDictionary]) {
        $result = @{}
        foreach ($key in $InputObject.Keys) {
            $result[$key] = ConvertTo-DeepHashtable $InputObject[$key]
        }
        return $result
    }

    if ($InputObject -is [pscustomobject]) {
        $result = @{}
        foreach ($property in $InputObject.PSObject.Properties) {
            $result[$property.Name] = ConvertTo-DeepHashtable $property.Value
        }
        return $result
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
        $items = New-Object System.Collections.ArrayList
        foreach ($item in $InputObject) {
            [void]$items.Add((ConvertTo-DeepHashtable $item))
        }
        return ,$items.ToArray()
    }

    return $InputObject
}

function Merge-DeepHashtable {
    param([object]$Base, [object]$Override)

    if ($null -eq $Base) {
        return ,$Override
    }
    if ($null -eq $Override) {
        return ,$Base
    }

    $baseIsMap = $Base -is [System.Collections.IDictionary]
    $overrideIsMap = $Override -is [System.Collections.IDictionary]
    if (-not $baseIsMap -or -not $overrideIsMap) {
        return ,$Override
    }

    $result = @{}
    foreach ($key in $Base.Keys) {
        $result[$key] = $Base[$key]
    }
    foreach ($key in $Override.Keys) {
        if ($result.ContainsKey($key)) {
            $result[$key] = Merge-DeepHashtable $result[$key] $Override[$key]
        }
        else {
            $result[$key] = $Override[$key]
        }
    }
    return $result
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object]$Value,
        [switch]$NoMerge
    )

    $final = $Value
    if (-not $NoMerge -and -not $script:Force -and (Test-Path $Path)) {
        try {
            $existing = Get-Content $Path -Raw | ConvertFrom-Json
            $base = ConvertTo-DeepHashtable $existing
            $over = ConvertTo-DeepHashtable $Value
            $final = Merge-DeepHashtable $base $over
        }
        catch {
            Write-Warn "Existing JSON at $Path is invalid; replacing it."
        }
    }

    $json = ConvertTo-Json -InputObject $final -Depth 30
    Backup-File $Path
    Write-Utf8File -Path $Path -Content ($json + "`r`n")
}

function Set-ManagedBlock {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Begin,
        [Parameter(Mandatory = $true)][string]$End,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $existing = ''
    if (Test-Path $Path) {
        $existing = Get-Content $Path -Raw
    }

    $block = "$Begin`r`n$Content`r`n$End"
    $pattern = '(?s)' + [regex]::Escape($Begin) + '.*?' + [regex]::Escape($End)

    if ($existing -match $pattern) {
        $updated = [regex]::Replace($existing, $pattern, { param($match) $block })
    }
    elseif ($existing.Length -gt 0) {
        $updated = $existing.TrimEnd() + "`r`n`r`n" + $block + "`r`n"
    }
    else {
        $updated = $block + "`r`n"
    }

    if ($updated -eq $existing) {
        Write-Skip "$Path already contains the managed block."
        return
    }

    Backup-File $Path
    Write-Utf8File -Path $Path -Content $updated
    Write-Ok "updated $Path"
}

function New-Shortcut {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Target,
        [string]$Arguments = '',
        [string]$WorkingDirectory = '',
        [string]$IconLocation = ''
    )

    if ($script:DryRun) {
        Write-Detail "[dry-run] shortcut $Path -> $Target $Arguments"
        return
    }

    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($Path)
    $shortcut.TargetPath = $Target
    if ($Arguments) { $shortcut.Arguments = $Arguments }
    if ($WorkingDirectory) { $shortcut.WorkingDirectory = $WorkingDirectory }
    if ($IconLocation) { $shortcut.IconLocation = $IconLocation }
    $shortcut.Save()
    Write-Ok "shortcut $Path"
}


function Test-WingetPackage {
    param([Parameter(Mandatory = $true)][string]$Id)

    if ($null -eq (Get-CommandPath 'winget')) { return $false }

    $output = & winget list --id $Id --exact --accept-source-agreements 2>$null
    if ($LASTEXITCODE -ne 0) { return $false }
    return (($output -join "`n") -match [regex]::Escape($Id))
}

function Install-WingetPackage {
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [string]$Name = $Id
    )

    if (Test-WingetPackage -Id $Id) {
        Write-Skip "$Name is already installed."
        return
    }

    Write-Detail "installing $Name ($Id)"
    $arguments = @(
        'install', '--id', $Id, '--exact',
        '--accept-package-agreements', '--accept-source-agreements',
        '--silent'
    )
    $code = Invoke-External -FilePath 'winget' -ArgumentList $arguments -AllowFailure
    if ($code -ne 0) {
        Write-Warn "$Name installer returned exit code $code. Check the winget output above."
    }
    else {
        Write-Ok "$Name installed."
    }
}
