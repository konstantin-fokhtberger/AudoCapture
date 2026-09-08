# Test Strategy
## Test Scenarios
1. Session folder creation and cleanup.
2. Metadata writing and serialization.
3. Session-plan construction and track configuration normalization.
4. Recording manager startup success and cleanup on failure.
5. Permission-denied handling.
6. Single-track degraded startup handling.
7. Stop-time partial encoding failure handling.
8. View-model state transitions, including termination preparation.
9. Concurrent capture startup orchestration.
10. Inactive-track artifact cleanup after degraded startup.

## Automated Coverage
Current SwiftPM tests cover:
- `AudioSyncCoordinatorTests`
- `RecordingDirectoryManagerTests`
- `MetadataWriterTests`
- `RecordingManagerTests`
- `RecordingViewModelTests`

Smoke validation:
- `AudoCaptureSmokeChecks` exercises the package in a hermetic temporary directory.

## Latest Validation
- Date: 2026-04-29
- `swift build`: passed, no CoreAudio device-name warning observed.
- `swift test`: passed, 19 Swift Testing tests in 5 suites, 0 failures.
- `swift run AudoCaptureSmokeChecks`: passed.

## Manual Test Cases
- Built-in microphone + system audio on a normal meeting session.
- USB microphone + system audio.
- Bluetooth microphone + system audio.
- Permission denial and permission recovery through System Settings.
- Stop during active recording and app termination during recording.
- Missing `ffmpeg` with `lame` fallback.

## Edge Cases
- One capture service fails to start.
- A device disappears before `stopRecording()`.
- MP3 encoding succeeds for one track and fails for the other.
- No display is available for `ScreenCaptureKit`.
- Session directory creation fails.

## Known Gaps
- No automated end-to-end runtime validation against real audio devices.
- No automated proof of long-session drift behavior.
- No automated real-device verification that startup skew stays within an acceptable bound.
- No automated external-process test for MP3 encoder timeout or cancellation behavior; the implementation is covered by code review and normal encoding failure metadata flow.
