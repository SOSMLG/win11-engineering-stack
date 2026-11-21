function Invoke-Packages {
    Write-Step 'Packages: winget readiness'

    $winget = Get-CommandPath 'winget'
    if (-not $winget) {
        Write-Skip 'winget is not installed. Manual install IDs are listed in README.md.'
        Write-Detail 'The apps module will skip every package that needs winget.'
        return
    }

    $version = (& winget --version 2>$null) -join ''
    Write-Detail "winget: $version"

    if ($script:DryRun) {
        Write-Detail '[dry-run] refresh winget sources.'
    }
    else {
        $code = Invoke-External -FilePath 'winget' -ArgumentList @('source', 'update', '--name', 'winget') -AllowFailure
        if ($code -ne 0) {
            Write-Warn 'winget source update failed; installs may use stale metadata.'
        }
        else {
            Write-Ok 'winget sources refreshed.'
        }
    }

    $scoop = Get-CommandPath 'scoop'
    if ($scoop) { Write-Detail "scoop: $scoop" } else { Write-Skip 'scoop not installed (optional).' }
}
