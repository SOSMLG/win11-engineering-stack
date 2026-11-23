# Consolidation plan: single installer (daily + IoT)

Status: planned. Front door already unified (`Install.ps1` + `Setup.cmd`).

## Goal
One `.ps1` installer and one `.cmd`, supporting both daily and IoT profiles.

## Current state
- `Install.ps1` (root) routes by `-Profile daily|iot`.
- `scripts/Install.ps1` implements daily (modular, stateful).
- `install-Win-Iot.ps1` implements IoT (monolithic, 64 KB).
- `Validate.ps1` (root) routes by profile.

## Phases
1. Extract IoT phases into `scripts/modules/iot/*.ps1` mirroring daily's module layout.
2. Add an `-Profile`-aware module selector in `scripts/Install.ps1`; IoT runs its module set.
3. Port IoT state/idempotency helpers to the shared `scripts/lib/Common.ps1`.
4. Delete `install-Win-Iot.ps1`; update ventoy/docs (already front-door routed).
5. Merge daily + IoT validation into `scripts/Validate.ps1`.
6. Update `AGENTS.md`, `README.md`, `QUICKSTART.md`, `docs/CLI.md`.

## Guardrails
- No behavior change per phase; verify with `Install.ps1 -Profile <p> -DryRun` and `Validate.ps1 -Profile <p>`.
- One phase per PR; keep diffs small.
- Do not remove `install-Win-Iot.ps1` until phase 4 tests pass.

## First step (phase 1)
Create `scripts/modules/iot/` with one file per IoT phase, sourced by the future unified installer. No wiring yet.