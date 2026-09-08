# Report: Recommendation Remediation
## Problem
The latest active review artifact identified five follow-ups that should be addressed before treating the MVP implementation as aligned with the documented risk-closure plan.

## Investigation
Reviewed:
- `docs/07-reports/2026-04-29_code-review-and-test-results.md`
- active documentation under `docs/00-overview` through `docs/08-changelog`
- `RecordingManager`
- `ProcessMP3Encoder`
- `MicrophoneDeviceCatalog`
- `RecordingManagerTests`

## Findings
- Permission handling still used an all-or-nothing `requestRequiredPermissions()` gate before single-track fallback could run.
- `RecordingManager` started microphone and system capture sequentially.
- A failed or skipped capture path could leave an inactive PCM file outside `metadata.json`.
- `ProcessMP3Encoder` waited indefinitely for encoder subprocess completion.
- `MicrophoneDeviceCatalog.name(for:)` still used the CoreAudio `CFString` pointer pattern that produced a Swift warning.

## Resolution
- `RecordingManager.startRecording()` now requests permissions best-effort, derives per-track availability from `PermissionsSnapshot`, and allows degraded single-track startup when exactly one track is available.
- Permitted capture services now start concurrently through `async let`.
- Inactive capture services are stopped when needed and their PCM artifacts are removed before metadata can omit them.
- `ProcessMP3Encoder` now has a default timeout and terminates the encoder subprocess on timeout or task cancellation.
- CoreAudio device-name lookup now uses an unmanaged `CFString` result instead of passing a `CFString` object reference directly as raw mutable memory.
- Added tests for permission-denied fallback, inactive artifact cleanup, and concurrent manager startup.

## Validation
- `swift build`: passed.
- `swift test`: passed, 19 Swift Testing tests in 5 suites, 0 failures.
- `swift run AudoCaptureSmokeChecks`: passed.
- The previously observed CoreAudio warning was not emitted during validation.

## Follow-ups
- Real audio-device validation is still required for hardware-specific behavior and long-session drift.
- MP3 timeout behavior should be covered by an external-process integration test if the project later standardizes test fixtures for local executable stubs.
