# Step 04. Single-Track Fallback

Date: 2026-04-17

## Goal

Close the requirement that says:

- if one stream is unavailable, the app should clearly communicate that fact
- and continue with the available stream when it is safe to do so

## Policy Chosen

The app now uses this startup policy:

- if both microphone and system audio start successfully:
  - record both tracks normally
- if exactly one track starts successfully:
  - continue recording with the available track
  - persist a warning in session metadata
  - surface a visible notice in the UI
- if both tracks fail to start:
  - fail startup
  - clean up the session directory

## Changes

- `RecordingManager.startRecording(...)` now returns `RecordingStartupReport`
- startup attempts are evaluated per-capture instead of all-or-nothing
- `ActiveSession` now supports optional microphone/system capture handles
- post-processing only encodes tracks that were actually captured
- metadata now includes a dedicated `warnings` array
- `RecordingViewModel` surfaces degraded-startup warnings via `noticeMessage`
- SwiftUI now renders a `Session Notice` box for nonfatal startup degradation

## Files touched

- `Sources/AudoCaptureCore/Models/RecordingModels.swift`
- `Sources/AudoCaptureCore/Recording/RecordingDependencies.swift`
- `Sources/AudoCaptureCore/Recording/RecordingManager.swift`
- `Sources/AudoCaptureCore/Recording/RecordingViewModel.swift`
- `Sources/AudoCaptureApp/ContentView.swift`
- `Tests/AudoCaptureCoreTests/RecordingManagerTests.swift`
- `Tests/AudoCaptureCoreTests/RecordingViewModelTests.swift`
- `Tests/AudoCaptureCoreTests/MetadataWriterTests.swift`
- `Sources/AudoCaptureSmokeChecks/main.swift`

## Verification

Automated verification added:

- `startRecordingFallsBackToSystemOnlyWhenMicrophoneFails`
- `startRecordingSurfacesDegradedStartupWarning`
- `startRecordingCleansUpSessionDirectoryWhenBothCapturePipelinesFail`

Validation status after this step:

- `swift build` passed
- `swift test` passed
- `swift run AudoCaptureSmokeChecks` passed

## Important Note

This policy is intentionally conservative about user honesty:

- it never silently pretends both tracks are present when only one started
- warnings are preserved in metadata and shown in the UI

That makes the fallback behavior acceptable for MVP without hiding degraded capture quality.
