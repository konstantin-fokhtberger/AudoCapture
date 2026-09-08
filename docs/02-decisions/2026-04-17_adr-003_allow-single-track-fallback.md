# ADR-003: Allow Honest Single-Track Fallback On Startup
## Status
accepted

## Context
The requirements prefer dual-track capture, but real macOS permission, device, or startup issues can prevent one pipeline from starting while the other remains usable.

## Decision
If exactly one capture pipeline starts successfully, continue the session with the available track, persist warnings in metadata, and surface the degraded state in the UI.

## Alternatives considered
- Fail the entire session if either track fails: simpler semantics, but loses usable recordings.
- Continue silently with one track: better continuity, but misleading for the user and downstream tooling.

## Consequences
- Metadata and UI must distinguish degraded-but-valid sessions from full dual-track sessions.
- Post-processing status must be computed against the set of active tracks, not a fixed expectation of two outputs.

## References
- `docs/01-requirements/2026-04-17_requirements-v1.md`
- `Sources/AudoCaptureCore/Recording/RecordingManager.swift`
- `Sources/AudoCaptureCore/Recording/RecordingViewModel.swift`
