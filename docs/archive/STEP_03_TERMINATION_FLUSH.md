# Step 03. Termination Flush

Date: 2026-04-17

## Goal

Close the reliability gap from `Requirements.md` around best-effort flush and preservation of
already-recorded data when the app is being terminated gracefully.

## Changes

- added `prepareForTermination()` to `RecordingViewModel`
- added `shouldDelayTermination` so the app layer can decide whether to block termination briefly
- introduced a shared `ApplicationModel` so the app delegate and UI use the same recording state
- added `AppDelegate` with `applicationShouldTerminate(_:)`
- when the app is closed during recording:
  - termination is delayed
  - recording is stopped with `openFolder: false`
  - post-processing is allowed to finish best effort
  - termination resumes after the flush attempt

## Files touched

- `Sources/AudoCaptureCore/Recording/RecordingViewModel.swift`
- `Sources/AudoCaptureApp/ApplicationModel.swift`
- `Sources/AudoCaptureApp/AppDelegate.swift`
- `Sources/AudoCaptureApp/AudoCaptureApp.swift`
- `Sources/AudoCaptureApp/ContentView.swift`
- `Tests/AudoCaptureCoreTests/RecordingViewModelTests.swift`

## Outcome

The app now has graceful-termination handling for active recording sessions.

This is intentionally framed as best effort:

- it helps on normal application termination
- it does not claim to survive hard kills, kernel panics, or sudden power loss

## Verification

Automated verification added:

- `prepareForTerminationStopsAnActiveRecordingWithoutOpeningFolder`

Validation rerun:

- `swift build` passed
- `swift test` passed
- `swift run AudoCaptureSmokeChecks` passed
