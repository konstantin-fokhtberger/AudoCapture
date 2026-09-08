# Step 01. Permission UX

Date: 2026-04-17

## Goal

Close the gap from `Requirements.md` that says the app should:

- show a clear permission error
- explain what must be enabled
- offer opening System Settings when possible

## Changes

- extended the core permission abstraction so permission settings can be opened through the
  injected controller path
- exposed two explicit actions from `RecordingViewModel`:
  - `openMicrophoneSettings()`
  - `openScreenRecordingSettings()`
- updated the SwiftUI error area to show actionable buttons when permissions are missing:
  - `Open Microphone Settings`
  - `Open Screen Recording Settings`

## Files touched

- `Sources/AudoCaptureCore/Recording/RecordingDependencies.swift`
- `Sources/AudoCaptureCore/Recording/RecordingManager.swift`
- `Sources/AudoCaptureCore/Recording/RecordingViewModel.swift`
- `Sources/AudoCaptureApp/ContentView.swift`

## Outcome

This closes the permission-UX gap at the UI level.

The app now has:

- user-visible permission failures
- actionable navigation to the relevant macOS privacy panes

## Remaining Follow-Up

This step does not yet address:

- microphone device selection
- single-track fallback behavior
- app termination flush handling
