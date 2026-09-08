# Project Overview
## Metadata
- Date: 2026-04-17
- Author: Codex
- Status: active

## Objective
AudoCapture is a local macOS desktop app for manual meeting recording. It captures two separate audio tracks during an online meeting: the user's microphone and the system audio heard through macOS output.

## Product Summary
- Platform: macOS Ventura or newer
- Language: Swift
- UI: SwiftUI
- Mic capture: `AVAudioEngine`
- System audio capture: `ScreenCaptureKit`
- Post-processing: `ffmpeg` with `lame` fallback
- Storage model: per-session folder with PCM originals, MP3 derivatives, and `metadata.json`

## User Flow
1. User launches the app and sees `idle`.
2. User refreshes permissions or microphone selection if needed.
3. User starts recording.
4. The app requests microphone and screen recording permissions.
5. The app creates a session folder and starts mic/system capture.
6. User stops recording.
7. The app finalizes PCM files, encodes MP3 files, writes metadata, and opens the output folder.

## Deliverables Per Session
- `mic.wav` when microphone capture was active
- `system.wav` when system capture was active
- `mic.mp3` when microphone encoding succeeded
- `system.mp3` when system encoding succeeded
- `metadata.json`

## Current Project Status
The repository contains an implemented MVP with:
- explicit recording lifecycle states
- microphone selection UI with best-effort device binding
- degraded single-track fallback when exactly one capture pipeline starts
- graceful stop-time metadata persistence and post-processing
- unit tests for deterministic core behavior

## Documentation Rule
The operational project context must live in the structured `docs` tree. Historical notes, one-off reviews, and superseded markdown files are archived under `docs/archive`.
