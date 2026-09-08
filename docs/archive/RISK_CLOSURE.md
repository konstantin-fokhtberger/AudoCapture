# Risk Closure Log

Last updated: 2026-04-17

This document tracks how the previously identified MVP risks were closed, step by step.

## Step 1. Make orchestration testable

Changes:

- introduced protocol-based dependencies for `RecordingManager`
- added injectable capture factory, permissions provider, and folder opener
- moved `RecordingViewModel` into `AudoCaptureCore` for direct test coverage

Why:

- the original wiring depended on concrete runtime services, which made failure-path testing hard
- closing the important risks required deterministic test doubles

Result:

- core behavior is now testable without real audio devices or real permissions

## Step 2. Close startup cleanup risk

Changes:

- `RecordingManager.startRecording()` now removes the just-created session directory when startup
  fails after directory creation
- `RecordingDirectoryManager` now exposes session-directory cleanup support

Why:

- a failed startup should not leave abandoned session folders behind

Verification:

- `startRecordingCleansUpSessionDirectoryWhenCaptureStartupFails`

## Step 3. Close permission-flow regression risk

Changes:

- added explicit automated coverage for denied microphone permission during startup

Why:

- permission denial is one of the most important real-world failure paths for this app

Verification:

- `startRecordingStopsBeforeDirectoryCreationWhenPermissionsAreDenied`

## Step 4. Close partial encoding failure risk

Changes:

- added automated coverage for one MP3 encode succeeding while the other fails
- confirmed metadata persists and reports `partialFailure`

Why:

- the product requirement says PCM originals must survive MP3 encoding failures

Verification:

- `stopRecordingPersistsMetadataWhenSecondEncoderFails`

## Step 5. Close device-disconnect reporting risk

Changes:

- added automated coverage for stop-time capture failure
- ensured such failures are preserved in `metadata.errors`

Why:

- runtime device changes are common for Bluetooth and external audio hardware

Verification:

- `stopRecordingCollectsRuntimeStopFailuresAsErrors`

## Step 6. Close UI-state race risk

Changes:

- preserved explicit `starting` state
- added automated tests for:
  - `starting -> recording`
  - `recording -> processing -> completed`
  - failure -> `failed`

Why:

- the UI must not offer `Stop` before a real session exists

Verification:

- `startRecordingMovesThroughStartingIntoRecording`
- `stopRecordingMovesThroughProcessingIntoCompleted`
- `startRecordingSetsFailedStateWhenManagerThrows`

## Step 7. Close display-selection ambiguity

Changes:

- added explicit display selection policy for system audio capture
- prefer the main display and fall back to the first available display
- persist the chosen source name in metadata

Why:

- “first display in the array” is an unstable implicit policy

Verification:

- code review of `DisplaySelectionPolicy`
- manual runtime verification still required for actual multi-display behavior

## Step 8. Close sync observability gap

Changes:

- added `trackMetrics` to metadata
- added `syncDiagnostics` to metadata
- persist per-track frame counts and derived durations

Why:

- sample-accurate synchronization cannot be guaranteed across the two Apple APIs
- the right mitigation for MVP is observability, not pretending the clocks are identical

Verification:

- metadata tests and `RecordingManager` tests now exercise the new fields

## Step 9. Close permission UX gap

Changes:

- surfaced explicit System Settings actions in the UI
- wired them through `RecordingViewModel` and `RecordingManager`
- preserved the existing actionable permission error text

Why:

- the original requirements explicitly asked to offer opening System Settings when possible

Verification:

- code review of `ContentView`, `RecordingViewModel`, and permission controller wiring
- manual runtime click-through still required on macOS app launch

## Step 10. Close default-input-only gap

Changes:

- added microphone inventory via CoreAudio
- added microphone selection in the SwiftUI UI
- passed selected microphone IDs through the controller layer
- implemented best-effort engine device binding for microphone capture

Why:

- the original requirements explicitly called for recording from a selected microphone device

Verification:

- `refreshMicrophonesSelectsDefaultDevice`
- full runtime validation still required for built-in, USB, and Bluetooth microphones

## Step 11. Close graceful-termination flush gap

Changes:

- added a termination-aware recording flush path in `RecordingViewModel`
- added `NSApplicationDelegate` integration to delay termination briefly
- added a shared app model so the delegate and the UI coordinate around the same recording state

Why:

- the requirements called for best-effort preservation of already-captured data when the app is
  being terminated

Verification:

- `prepareForTerminationStopsAnActiveRecordingWithoutOpeningFolder`
- build, tests, and smoke checks all passed after the change

## Step 12. Close single-track fallback gap

Changes:

- startup now degrades to a one-track session when exactly one capture pipeline starts
- startup still fails when both pipelines fail
- warnings are surfaced both in metadata and in the UI

Why:

- the original requirements explicitly allowed continuing with one stream when that is safe and
  clearly communicated

Verification:

- `startRecordingFallsBackToSystemOnlyWhenMicrophoneFails`
- `startRecordingSurfacesDegradedStartupWarning`
- `startRecordingCleansUpSessionDirectoryWhenBothCapturePipelinesFail`

## Validation Status

The following checks passed after the risk-closure changes:

```bash
env HOME=/Users/konstantinfokhtberger/Documents/Codex/AudoCapture/.tmp-home \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH=/Users/konstantinfokhtberger/Documents/Codex/AudoCapture/.build/ModuleCache \
swift build
```

```bash
env HOME=/Users/konstantinfokhtberger/Documents/Codex/AudoCapture/.tmp-home \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH=/Users/konstantinfokhtberger/Documents/Codex/AudoCapture/.build/ModuleCache \
swift test
```

Result:

- 10 tests passed

```bash
env HOME=/Users/konstantinfokhtberger/Documents/Codex/AudoCapture/.tmp-home \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH=/Users/konstantinfokhtberger/Documents/Codex/AudoCapture/.build/ModuleCache \
swift run AudoCaptureSmokeChecks
```

Result:

- smoke checks passed
