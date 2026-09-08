# ADR-002: Normalize Capture Outputs To 48 kHz PCM
## Status
accepted

## Context
Microphone devices and ScreenCaptureKit may produce different native formats. The project needs predictable files and stable post-processing without adding heavy realtime logic.

## Decision
Normalize capture output to PCM WAV at `48 kHz` with:
- microphone: mono, 16-bit
- system audio: stereo, 16-bit

## Alternatives considered
- Preserve each source's native format: fewer conversions, but more variability in files and encoding pipeline.
- Normalize both tracks to stereo: simpler downstream assumptions, but wastes space for mono microphone input.

## Consequences
- Realtime conversion remains in the capture path when source formats differ.
- Resulting artifacts are predictable for MP3 encoding and metadata reporting.
- Duration diagnostics can compare tracks in a consistent sample-rate space.

## References
- `docs/01-requirements/2026-04-17_requirements-v1.md`
- `Sources/AudoCaptureCore/Recording/AudioSyncCoordinator.swift`
- `Sources/AudoCaptureCore/Capture/AudioConversion.swift`
