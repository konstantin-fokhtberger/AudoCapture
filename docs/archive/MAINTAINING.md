# Maintaining AudoCapture

## Test And Build Workflow

Use these commands when validating package changes:

```bash
swift build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
swift run AudoCaptureSmokeChecks
```

Why this matters:

- In this repo, `swift build` works with the current local setup.
- `swift test` may fail if the active developer directory points to Command Line Tools
  instead of the full Xcode install.
- Using `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` avoids changing the
  global `xcode-select` setting while still giving SwiftPM access to the full Apple
  test toolchain.

## UI State Rules

`RecordingViewModel` has a deliberate `starting` state.

- Do not move the UI into `recording` before `RecordingManager.startRecording()` finishes.
- The Stop button must remain disabled during permission prompts and startup.
- This prevents a race where the UI tries to stop a session that does not exist yet.

If the startup flow changes, preserve that invariant.

## Smoke Check Rules

`AudoCaptureSmokeChecks` is intentionally isolated from real user data.

- It must only create files inside a temporary directory.
- It must not write into `~/Documents/Recordings`.
- It should clean up any temporary directory it creates.

If the smoke check grows, keep it deterministic and side-effect-light.

## Current Automated Coverage

SwiftPM tests currently cover:

- `RecordingDirectoryManager` override-root behavior
- `MetadataWriter` JSON persistence
- `AudioSyncCoordinator` session-plan construction
- `RecordingManager` startup cleanup on failed capture start
- `RecordingManager` permission-denied startup
- `RecordingManager` partial-failure behavior during stop/encoding
- `RecordingManager` stop-time device failure reporting
- `RecordingViewModel` startup/stop/failure state transitions

The highest-value remaining validation is manual runtime verification of actual audio capture and
permissions on a real macOS app session.

## Concurrency Note

`AudioConversion.makeCopy` uses a small reference-type state object for the converter input
closure. That is intentional: it avoids Swift 6 sendable-capture diagnostics from mutating a
captured local variable inside a concurrently-executing closure.

## Metadata Diagnostics

`RecordingSessionMetadata` now carries two diagnostic structures:

- `trackMetrics`
- `syncDiagnostics`

Use them when investigating:

- mic/system duration mismatch
- drift over long sessions
- partial capture failure reports

The diagnostics are intended for observability. They do not imply sample-accurate sync.
