# Report: Code Review And Test Results
## Problem
The project needed a fresh project review, including the active `docs` tree, code review findings, automated test results, and recommendations for the next implementation iterations.

## Investigation
Reviewed:
- `README.md`
- `Package.swift`
- active documentation under `docs/00-overview` through `docs/08-changelog`
- all ADR files under `docs/02-decisions`
- core recording, capture, persistence, encoding, permission, and view-model code
- unit tests under `Tests/AudoCaptureCoreTests`
- smoke check executable under `Sources/AudoCaptureSmokeChecks`

Executed:
- `swift test`
- `swift run AudoCaptureSmokeChecks`
- `swift build`

## Findings
- P1: Single-track fallback is skipped on permission denial. `RecordingManager.startRecording()` calls `requestRequiredPermissions()` before creating either capture service, so denial of either microphone or Screen Recording permission aborts the whole session instead of allowing an honest degraded single-track session when the other track is available.
- P2: Failed startup can leave unreported WAV artifacts. A capture service can prepare its writer and create `mic.wav` or `system.wav` before failing startup; the manager then omits that track from metadata without removing or reporting the file.
- P2: Encoder subprocess can hang stop and app termination. `ProcessMP3Encoder` calls `Process.waitUntilExit()` without a timeout or cancellation path, so a stalled `ffmpeg` or `lame` process can keep the app in `processing` indefinitely.
- P3: CoreAudio device-name lookup emits a Swift warning. `MicrophoneDeviceCatalog.name(for:)` reads a `CFString` through an unsafe raw pointer pattern that Swift warns is likely incorrect for object references.

## Test Results
- `swift test`: passed. Swift Testing reported 16 tests in 5 suites with 0 failures.
- `swift run AudoCaptureSmokeChecks`: passed with `Smoke checks passed.`
- `swift build`: passed.

Build warning observed:
- `Sources/AudoCaptureCore/Capture/MicrophoneDeviceCatalog.swift`: Swift warns about forming an `UnsafeMutableRawPointer` to a `CFString` variable while reading the CoreAudio device name.

## Resolution
The original review made no source code changes. The follow-up remediation is now tracked in `docs/07-reports/2026-04-29_recommendation-remediation-report.md`.

## Follow-ups
1. Closed in remediation: permission handling now supports single-track fallback when one permission is denied and the other track is available.
2. Closed in remediation: inactive startup artifacts are removed before metadata is written.
3. Closed in remediation: MP3 subprocess execution now has timeout and cancellation handling.
4. Closed in remediation: CoreAudio `CFString` lookup was rewritten and the build warning no longer appears.
5. Closed in remediation: permitted capture services are started concurrently at the manager level.
6. Remaining: validate real-device timing and drift manually on target macOS hardware.
