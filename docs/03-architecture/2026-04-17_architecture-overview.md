# Architecture Overview
## Components
- `AudoCaptureApp`: SwiftUI app entry, app delegate, shared application model, and main window UI.
- `RecordingViewModel`: main UI-facing state machine and command surface.
- `RecordingManager`: actor that orchestrates permissions, capture startup, stop, encoding, metadata, and folder opening.
- `MicrophoneCaptureService`: microphone capture through `AVAudioEngine` with optional best-effort device binding.
- `SystemAudioCaptureService`: system audio capture through `ScreenCaptureKit`.
- `AudioSyncCoordinator`: session plan builder and normalized format source.
- `PCMFileWriter`: realtime PCM writer.
- `ProcessMP3Encoder`: subprocess-based MP3 encoding wrapper.
- `MetadataWriter`: persistence for `RecordingSessionMetadata`.
- `PermissionsManager`: permission checks, requests, and settings deep links.

## Data Flow
1. UI requests `startRecording()`.
2. `RecordingManager` requests permissions and derives per-track availability.
3. `AudioSyncCoordinator` creates a session plan and normalized formats.
4. `RecordingDirectoryManager` creates the session folder and artifact paths.
5. Permitted capture services start concurrently and stream PCM data into per-track writers.
6. UI requests `stopRecording()`.
7. Capture services stop and flush writers.
8. MP3 encoder runs on the generated WAV files.
9. Metadata is assembled and written to disk.
10. The output folder is opened.

## Audio Pipeline
- Microphone path:
  - `AVAudioEngine.inputNode`
  - tap installation
  - optional `AVAudioConverter`
  - `PCMFileWriter`
- System path:
  - `SCShareableContent`
  - selected `SCDisplay`
  - `SCStream` audio output
  - optional `AVAudioConverter`
  - `PCMFileWriter`

## Recording Lifecycle
- `idle`
- `starting`
- `recording`
- `processing`
- `completed`
- `failed`

The explicit `starting` state is intentional so the UI cannot stop a session before the manager has a valid active session.

## Key Design Decisions
- Realtime capture is separate from post-processing.
- Session metadata includes diagnostics and warnings, not just happy-path outputs.
- `RecordingManager` is an actor to serialize session lifecycle changes.
- Core logic is isolated from app UI so it can be tested with injected dependencies.
- Startup is best-effort concurrent for permitted tracks; unavailable tracks are represented as degraded-startup warnings.

## Known Architectural Gap
The architecture still does not provide sample-accurate cross-device clock alignment. It now reduces startup skew through concurrent manager orchestration, but long-session drift must be validated on real devices.
