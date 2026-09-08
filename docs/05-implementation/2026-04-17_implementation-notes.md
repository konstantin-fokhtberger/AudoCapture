# Implementation Notes
## Modules
- `Sources/AudoCaptureApp`
  - app bootstrap
  - app delegate termination handling
  - `ContentView`
- `Sources/AudoCaptureCore/Capture`
  - microphone capture
  - system audio capture
  - format conversion helpers
  - microphone catalog
- `Sources/AudoCaptureCore/Recording`
  - orchestration
  - dependencies
  - view model
  - sync coordinator
- `Sources/AudoCaptureCore/Persistence`
  - session folder creation
  - PCM file writing
- `Sources/AudoCaptureCore/Encoding`
  - MP3 encoding
- `Sources/AudoCaptureCore/Metadata`
  - metadata serialization
- `Sources/AudoCaptureCore/Logging`
  - application logging

## Key Classes
- `RecordingManager`: owns active session lifecycle and final metadata assembly.
- `RecordingViewModel`: bridges async manager calls into SwiftUI state.
- `MicrophoneCaptureService`: configures engine tap and optional device selection.
- `SystemAudioCaptureService`: configures `SCStream` and persists audio samples.
- `RecordingDirectoryManager`: builds timestamped folder layout under `~/Documents/Recordings`.

## Critical Flows
### Start
- request permissions and derive per-track availability from the current permission snapshot
- build normalized session plan
- create session folder
- create capture services
- start permitted capture services concurrently
- stop and remove artifacts for inactive capture services
- keep successful tracks and persist startup warnings

### Stop
- stop active capture services
- encode MP3 files for tracks that actually produced PCM files, with subprocess timeout and cancellation handling
- compute `postProcessingStatus` against active tracks
- write `metadata.json`
- optionally open the output folder

### Termination
- App delegate asks the view model whether termination should be delayed.
- If recording is active, stop and flush without opening the folder.

## Persistence Layout
- root: `~/Documents/Recordings/<yyyy-MM-dd-HHmmss>/`
- raw outputs: `mic.wav`, `system.wav`
- encoded outputs: `mic.mp3`, `system.mp3`
- metadata: `metadata.json`

## Known Tradeoffs
- Concurrent startup reduces manager-level start skew, but does not solve sample-accurate clock alignment across independent sources.
- Best-effort microphone binding is good enough for MVP but not equivalent to a dedicated CoreAudio routing stack.
- Metadata is richer than the original prompt and now includes warnings, track metrics, and sync diagnostics for investigation.
