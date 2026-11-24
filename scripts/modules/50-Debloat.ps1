function Invoke-DebloatModule {
    $skip = $false
    if ($null -ne (Get-Variable -Name NoDebloat -Scope Script -ErrorAction SilentlyContinue)) {
        $skip = [bool]$script:NoDebloat
    }
    Invoke-Debloat -Skip:$skip
}
