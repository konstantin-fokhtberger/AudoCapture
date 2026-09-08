# Step 02. Microphone Selection

Date: 2026-04-17

## Goal

Reduce the gap from `Requirements.md` around recording from a selected microphone instead of only
the current macOS default input.

## Changes

- added CoreAudio-based microphone inventory via `MicrophoneDeviceCatalog`
- introduced `MicrophoneDevice` model for UI and controller wiring
- exposed available microphones through `RecordingManager` and `RecordingViewModel`
- added a microphone picker to the SwiftUI UI
- passed the selected microphone device ID into the recording startup path
- implemented best-effort device binding in `MicrophoneCaptureService` using
  `AudioUnitSetProperty(... kAudioOutputUnitProperty_CurrentDevice ...)`

## Files touched

- `Sources/AudoCaptureCore/Capture/MicrophoneDeviceCatalog.swift`
- `Sources/AudoCaptureCore/Capture/MicrophoneCaptureService.swift`
- `Sources/AudoCaptureCore/Recording/RecordingDependencies.swift`
- `Sources/AudoCaptureCore/Recording/RecordingManager.swift`
- `Sources/AudoCaptureCore/Recording/RecordingViewModel.swift`
- `Sources/AudoCaptureApp/ContentView.swift`
- `Tests/AudoCaptureCoreTests/RecordingViewModelTests.swift`
- `Tests/AudoCaptureCoreTests/RecordingManagerTests.swift`

## Outcome

The app now supports:

- listing available microphone-capable devices
- selecting a preferred microphone in the UI before recording starts
- attempting to bind the recording engine to that selected microphone

## Important Limitation

This closes the product gap only on a best-effort basis.

`AVAudioEngine` on macOS is not the most reliable API for robust arbitrary device routing.
The implementation is intentionally honest about that:

- device inventory is explicit
- the selected device is passed into startup explicitly
- binding may still fail depending on the engine's I/O constraints and the device topology

If the selected microphone cannot be bound, startup fails with a clear device-selection error
instead of silently recording from the wrong device.

## Verification

Automated verification added:

- `refreshMicrophonesSelectsDefaultDevice`

Full validation still requires manual runtime testing on macOS with:

- built-in mic
- external USB mic
- Bluetooth headset
