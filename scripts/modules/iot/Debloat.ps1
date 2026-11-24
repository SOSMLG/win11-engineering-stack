# ---------- 3. one default debloat pass ----------
# Runs after apps and before configs. Missing AppX or task cmdlets are skips,
# not failures, so tiny11/AspectOS-style images keep going.
if ((-not $ConfigsOnly) -and (Should-Run 'debloat')) {
  Log 'Debloat...'
  Start-Phase 'debloat'
  Invoke-Debloat -Skip:$NoDebloat
  Stop-Phase
  Complete-Phase 'debloat'
} elseif ($ConfigsOnly) {
  Log 'Configs-only: debloat skipped.'
}
