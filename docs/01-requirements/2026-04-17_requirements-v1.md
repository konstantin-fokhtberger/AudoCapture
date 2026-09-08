# Requirements - Version 1
## Metadata
- Date: 2026-04-17
- Author: Codex
- Version: 1
- Status: approved

## Objective
Deliver an MVP macOS desktop application that records microphone and system audio into separate tracks for later transcription or review.

## Scope
Included in MVP:
- manual start and stop recording
- real-time local capture
- separate PCM originals for microphone and system audio
- MP3 conversion after capture stops
- per-session metadata persistence
- actionable permission and failure messaging

Out of scope:
- transcription
- cloud sync
- meeting-platform integrations
- hotkeys
- automatic start triggers
- track mixing or speaker diarization

## Functional Requirements
- The UI must expose `Start Recording`, `Stop Recording`, and visible state changes.
- The app must capture microphone audio and system audio as separate tracks.
- The app must create a dedicated session folder per recording under `~/Documents/Recordings/<timestamp>/`.
- The app must preserve PCM originals even if MP3 conversion fails.
- The app must write session metadata including timestamps, device/source information, track configuration, artifact paths, post-processing status, warnings, and errors.
- The app must explain missing permissions and offer a way to open the relevant System Settings panes.
- The app should continue with a single active track only when exactly one capture pipeline starts successfully and the user-visible state remains honest about the degraded session.

## Non-Functional Requirements
- Startup should be fast enough for manual use, targeting sub-second perceived latency where the OS allows it.
- Realtime capture must avoid CPU-heavy work other than unavoidable format conversion and PCM writing.
- The app must not crash when permissions are denied, devices disconnect, or MP3 encoding fails.
- The architecture must stay modular enough to add device selection, level meters, mixing, or transcription later.
- The app must remain local-only and avoid adding backend infrastructure.

## Acceptance Criteria
- Starting a session creates active capture for microphone and/or system audio according to runtime availability.
- Stopping a session produces PCM files for the captured tracks.
- MP3 derivatives are produced for the tracks whose encoding succeeded.
- `metadata.json` accurately describes the session outcome.
- The output folder opens after normal stop.
- Permission denial produces actionable messaging instead of silent failure.

## Open Questions
- Whether capture startup should be reworked from sequential to truly concurrent orchestration to reduce start skew.
- How much manual hardware validation is required before declaring USB and Bluetooth microphone support production-ready.
- Whether the session folder naming should stay at `yyyy-MM-dd-HHmmss` or be aligned more strictly to the originally suggested `yyyy-MM-dd-HHMM` format.
