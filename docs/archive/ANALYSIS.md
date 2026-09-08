# AudoCapture Analysis

Last reviewed: 2026-04-17

## Scope Snapshot

The current package implements the requested MVP shape:

- SwiftUI desktop UI
- manual `Start Recording` / `Stop Recording`
- microphone capture via `AVAudioEngine`
- system audio capture via `ScreenCaptureKit`
- separate PCM originals written as `mic.wav` and `system.wav`
- MP3 post-processing through `ffmpeg` with `lame` fallback
- session metadata persistence
- lightweight smoke checks and SwiftPM regression tests

## Current Module Layout

- `Sources/AudoCaptureApp`
  - app entry point
  - SwiftUI view
  - UI state management in `RecordingViewModel`
- `Sources/AudoCaptureCore`
  - capture modules
  - permissions
  - file persistence
  - metadata
  - logging
  - session orchestration
- `Sources/AudoCaptureSmokeChecks`
  - hermetic package-level smoke validation
- `Tests/AudoCaptureCoreTests`
  - focused regression tests for deterministic core logic

## Implementation Notes

### Recording lifecycle

`RecordingViewModel` uses a distinct `starting` state before transitioning to `recording`.
That is correct and should be preserved, because it keeps `Stop` disabled until:

- permission prompts finish
- both capture services are initialized
- `RecordingManager` actually has an active session

### Audio normalization

`AudioSyncCoordinator` defines a normalized capture plan:

- microphone: `48 kHz`, mono, PCM Int16
- system: `48 kHz`, stereo, PCM Int16

That is a pragmatic MVP choice because it makes downstream MP3 conversion predictable and
reduces format spread across different devices.

### Realtime path

The current realtime path is correctly separated from post-processing:

- capture services convert/write directly to PCM
- MP3 encoding is deferred until `stopRecording`

This matches the stated requirement to avoid CPU-heavy work during live recording.

## Validation Results

The following commands were re-run successfully with the full Xcode toolchain:

```bash
env HOME=/Users/konstantinfokhtberger/Documents/Codex/AudoCapture/.tmp-home \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH=/Users/konstantinfokhtberger/Documents/Codex/AudoCapture/.build/ModuleCache \
swift build
```

Result: success

```bash
env HOME=/Users/konstantinfokhtberger/Documents/Codex/AudoCapture/.tmp-home \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH=/Users/konstantinfokhtberger/Documents/Codex/AudoCapture/.build/ModuleCache \
swift test
```

Result: success, 3 tests passed

Result: success, 14 tests passed

- `RecordingDirectoryManagerTests`
- `MetadataWriterTests`
- `AudioSyncCoordinatorTests`
- `RecordingManagerTests`
- `RecordingViewModelTests`

```bash
env HOME=/Users/konstantinfokhtberger/Documents/Codex/AudoCapture/.tmp-home \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH=/Users/konstantinfokhtberger/Documents/Codex/AudoCapture/.build/ModuleCache \
swift run AudoCaptureSmokeChecks
```

Result: success

## Closed Risks

The earlier MVP risks have now been addressed as follows:

1. Startup cleanup
   `RecordingManager.startRecording()` now removes the just-created session directory if either
   capture pipeline fails during startup.

2. Permission-denied flow coverage
   Automated tests now cover a denied-permission startup path.

3. Partial MP3 failure coverage
   Automated tests now cover the case where one encoder pass succeeds and the other fails while
   preserving PCM outputs and metadata.

4. Device-disconnect style stop failure coverage
   Automated tests now cover stop-time capture failure propagation into `metadata.errors`.

5. View-model state transition coverage
   `RecordingViewModel` is now in the core module and has regression tests for:
   - `starting -> recording`
   - `recording -> processing -> completed`
   - startup failure -> `failed`

6. Multi-display selection policy
   `SystemAudioCaptureService` now uses an explicit display policy:
   - prefer the main display
   - fall back to the first available display
   - persist the selected source description in metadata

7. Sync observability
   Metadata now includes:
   - per-track frame counts
   - per-track estimated durations
   - sync diagnostics with absolute duration delta

8. Single-track fallback
   Startup now degrades to a one-track session when exactly one capture pipeline succeeds.
   The degradation is surfaced in both metadata and UI notices.

## Remaining Platform Limitations

These are no longer treated as project gaps; they are platform/API constraints that still apply:

1. Synchronization remains best effort, not sample-accurate.
   `AVAudioEngine` and `ScreenCaptureKit` do not provide a single shared capture clock.
   The code now exposes drift diagnostics rather than pretending to eliminate it.

2. System audio capture is still constrained by `ScreenCaptureKit`.
   It depends on screen-recording permission and display-based capture semantics.

3. End-to-end validation of real audio quality still requires a manual app run on macOS with:
   - microphone permission
   - screen recording permission
   - `ffmpeg` or `lame`

## Current Automated Coverage

Successful automated checks now include:

- `RecordingDirectoryManager` override-root behavior
- `MetadataWriter` JSON persistence
- `AudioSyncCoordinator` session-plan construction
- `RecordingManager` startup cleanup on capture failure
- `RecordingManager` permission-denied startup
- `RecordingManager` partial MP3 encoding failure
- `RecordingManager` stop-time device failure reporting
- `RecordingViewModel` startup, stop, and failure transitions
