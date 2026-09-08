# Remediation Plan After Second Review Pass

Date: 2026-04-17

Source review artifacts:

- [REVIEW_2026-04-17_SECOND_PASS.md](/Users/konstantinfokhtberger/Documents/Codex/AudoCapture/docs/REVIEW_2026-04-17_SECOND_PASS.md)
- [REQUIREMENTS_GAPS_2026-04-17.md](/Users/konstantinfokhtberger/Documents/Codex/AudoCapture/docs/REQUIREMENTS_GAPS_2026-04-17.md)

## Purpose

This plan turns the second-pass review findings into a concrete execution order.

The goal is to fix correctness gaps first, then startup behavior, then low-level cleanup, and
only after that reconcile the documentation.

## Priority Order

### Step 1. Fix `postProcessingStatus` for degraded one-track sessions

Why first:

- this is a metadata correctness bug
- it can mislabel a successful one-track session as a failure

Planned work:

- compute `postProcessingStatus` relative to the tracks that were actually active
- add regression tests for:
  - successful system-only session
  - successful mic-only session
  - active one-track session with encode failure

Expected outcome:

- metadata becomes truthful for degraded-but-successful sessions

Status:

- completed on 2026-04-17
- see [STEP_05_POSTPROCESSING_STATUS_FIX.md](/Users/konstantinfokhtberger/Documents/Codex/AudoCapture/docs/STEP_05_POSTPROCESSING_STATUS_FIX.md)

### Step 2. Restore truly concurrent startup while preserving degraded fallback

Why second:

- this is the most direct requirement mismatch left in the runtime flow
- the current implementation claims minimal-skew startup but no longer truly does it

Planned work:

- start mic and system capture concurrently again
- keep per-track success/failure collection
- preserve degraded fallback when exactly one track starts
- preserve cleanup when both fail

Expected outcome:

- startup behavior becomes closer to the requirement and to the documented claims

### Step 3. Fix the CoreAudio pointer warning in microphone device lookup

Why third:

- this is not the most severe product bug
- but low-level pointer warnings in CoreAudio interop should not be left unresolved

Planned work:

- rewrite the `CFString` property read in `MicrophoneDeviceCatalog`
- ensure the full Xcode toolchain build is warning-free in that code path

Expected outcome:

- safer CoreAudio interop and cleaner validation output

### Step 4. Reconcile documentation with actual behavior

Why last:

- docs should trail behavior changes, not predict them
- the review correctly identified drift caused by docs getting ahead of the code

Planned work:

- refresh:
  - `docs/ANALYSIS.md`
  - `docs/COMPLIANCE.md`
  - `docs/RISK_CLOSURE.md`
  - `docs/REQUIREMENTS_GAPS_2026-04-17.md`
- keep test counts and command recipes single-sourced and factual

Expected outcome:

- the project docs become trustworthy status reports again

## Validation Strategy

After each step:

- add or update targeted regression tests
- update a step-specific markdown artifact if behavior materially changes

After the final step:

- run:
  - `swift build`
  - `swift test`
  - `swift run AudoCaptureSmokeChecks`
- update review-linked docs with the final status
