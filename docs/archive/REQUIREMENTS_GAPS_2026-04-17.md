# Requirements Gap Snapshot

Date: 2026-04-17

This file records the remaining gaps and ambiguities after the second review pass.

## Still Strongly Aligned

- local macOS-only architecture
- separate mic/system PCM outputs
- MP3 post-processing after stop
- metadata persistence
- permission UX with actionable settings links
- hermetic smoke check
- regression tests for deterministic manager and view-model flows

## Remaining Gaps

### Concurrent dual-start behavior

Requirement source:

- `docs/Requirements.md` asks for synchronous stream start with minimal possible skew

Current state:

- current `RecordingManager.startRecording()` starts the two capture pipelines sequentially

Impact:

- this weakens the implementation relative to the requirement
- the current sync diagnostics are useful, but they do not close the startup-skew requirement

### Successful degraded sessions are underreported

Requirement source:

- if one stream is unavailable, continue safely and communicate clearly

Current state:

- startup fallback is implemented correctly
- post-processing status now evaluates only the tracks that were actually active in the session

Impact:

- metadata semantics now match the degraded-session policy
- no open gap remains here

### Real hardware proof is still manual

Requirement source:

- acceptable audio quality
- close duration alignment
- best-effort support for built-in, USB, and Bluetooth microphones

Current state:

- code structure supports the intended behavior
- automated tests cover deterministic logic only
- hardware behavior still requires manual validation

Impact:

- compliance should still be described as partial until that matrix is actually run

## Recommended Next Validation Matrix

Run and document:

1. Built-in mic + system audio on a single-display setup
2. USB mic + system audio
3. Bluetooth headset mic + system audio
4. Main-display change / multi-display system-audio capture behavior
5. Long-enough session to inspect `syncDiagnostics.absoluteDurationDeltaSeconds`

## Documentation Hygiene Rule

When a new behavior change lands in recording startup, fallback, or stop-time metadata logic,
update these files together:

- `docs/ANALYSIS.md`
- `docs/COMPLIANCE.md`
- `docs/RISK_CLOSURE.md`
- this file, if the requirement status materially changes
