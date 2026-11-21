function Invoke-Preflight {
    Write-Step 'Preflight: system and image checks'

    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $build = [int](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuildNumber
    $guardrails = Get-ImageGuardrails
    $script:Guardrails = $guardrails

    Write-Detail "OS:      $($os.Caption)"
    Write-Detail "Version: $($os.Version) (build $build)"
    Write-Detail "Arch:    $($os.OSArchitecture)"
    Write-Detail "Admin:   $(Test-Admin)"

    $drive = Get-PSDrive -Name C
    $freeGb = [math]::Round($drive.Free / 1GB, 1)
    Write-Detail "Free C:  $freeGb GB"
    if ($freeGb -lt 20) {
        Write-Warn 'Less than 20 GB free. TIA Portal and MATLAB need substantially more.'
    }

    Write-Step 'Image guardrails'
    $missing = @()
    if (-not $guardrails.DefenderCmdlet -and -not $guardrails.DefenderService) {
        $missing += 'Defender'
        Write-Fail 'Defender is missing. Real-time antivirus cannot be provided by this script.'
    }
    else {
        Write-Ok 'Defender present.'
    }

    if (-not $guardrails.WinSxS) {
        $missing += 'WinSxS'
        Write-Fail 'WinSxS is missing. .NET 3.5, IIS, and MSMQ cannot be enabled from this image.'
    }
    else {
        Write-Ok 'Component store present.'
    }

    if (-not $guardrails.Winget) {
        $missing += 'winget'
        Write-Skip 'winget is missing. The apps module will skip package installs; manual IDs are in README.md.'
    }
    else {
        Write-Ok 'winget present.'
    }

    if ($missing.Count -gt 0) {
        Write-Warn "This image is missing: $($missing -join ', ')."
        Write-Warn 'Rebuild with WinUtil/MicroWin keeping Defender, WinSxS, Windows Update, and App Installer.'
    }

    Write-Step 'Optional features'
    if (Test-Admin) {
        $features = @(
            'NetFx3',
            'IIS-WebServerRole',
            'IIS-ASPNET45',
            'IIS-ManagementConsole',
            'MSMQ-Server',
            'MSMQ-DCOMProxy',
            'WCF-HTTP-Activation45',
            'WCF-MSMQ-Activation45'
        )
        foreach ($feature in $features) {
            $state = Get-OptionalFeatureState -Name $feature
            Write-Detail ("{0,-28} {1}" -f $feature, $state)
        }
    }
    else {
        Write-Skip 'Feature state needs elevation; run Install.ps1 without -DryRun.'
    }

    Write-Step 'Environment'
    $longPaths = Get-PropValue (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name LongPathsEnabled -ErrorAction SilentlyContinue) 'LongPathsEnabled' 'unknown'
    Write-Detail "Long paths: $longPaths"
    Write-Detail "Pending reboot: $(Test-RebootPending)"
    Write-Detail "OMNIROUTE_API_KEY set: $([bool]$env:OMNIROUTE_API_KEY)"

    $winget = Get-CommandPath 'winget'
    if ($winget) { Write-Detail "winget: $winget" }

    try {
        Invoke-WebRequest -Uri 'https://api.github.com/zen' -UseBasicParsing -TimeoutSec 8 | Out-Null
        Write-Ok 'Internet reachable.'
    }
    catch {
        Write-Warn 'GitHub is not reachable. App downloads will fail until connectivity returns.'
    }

    Write-Step 'Backing up existing configs'
    $targets = Get-ConfigTargets
    foreach ($name in $targets.Keys) {
        $path = $targets[$name]
        if (Test-Path $path) {
            Backup-File $path
        }
    }

    if ($script:DryRun) {
        Write-Detail "[dry-run] state and logs would live in $script:StateRoot"
    }
    else {
        Write-Ok "state: $script:StateRoot"
    }
}
