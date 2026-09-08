# Requirements - Version 1.1
## Metadata
- Date: 2026-04-29
- Author: Codex
- Version: 1.1
- Status: approved

## Objective
Keep the original MVP objective from Version 1.0: a local macOS SwiftUI desktop app that records microphone audio and system audio into separate PCM tracks, then converts each available track to MP3 and writes session metadata.

## Scope
The scope remains unchanged:
- local single-user desktop app
- manual start and stop
- separate microphone and system-audio tracks
- PCM source preservation
- MP3 post-processing through external encoder subprocesses
- no transcription, cloud sync, meeting-platform integration, diarization, hotkeys, or track merging

## Functional Requirements
- Start must evaluate microphone and Screen Recording permissions independently.
- If exactly one permission or capture pipeline is available, the app may continue with a single-track degraded session and must surface the warning in UI and metadata.
- If a capture pipeline fails after preparing an output file, the inactive track artifact must be removed or otherwise reconciled so `metadata.json` does not omit an existing orphaned PCM file.
- Permitted microphone and system capture services must be started concurrently on a best-effort basis to reduce startup skew.
- MP3 encoding subprocesses must have a timeout and cancellation path so post-processing cannot hang indefinitely.

## Non-Functional Requirements
- The codebase should build without the previously observed CoreAudio `CFString` pointer warning.
- Existing PCM files must remain available if MP3 encoding fails or times out.
- Timeout failures must be represented as post-processing errors in metadata through the existing error collection flow.

## Acceptance Criteria
- Automated tests cover permission-denied single-track fallback behavior.
- Automated tests cover removal of inactive-track PCM files during degraded startup.
- Automated tests cover concurrent startup orchestration at the manager level.
- `swift build`, `swift test`, and `swift run AudoCaptureSmokeChecks` pass.
- No CoreAudio device-name warning is emitted during `swift build`.

## Open Questions
- Real-device end-to-end timing and drift behavior still requires manual validation on target macOS hardware.
- MP3 timeout duration is currently fixed at the encoder default and may later need UI or configuration exposure.
