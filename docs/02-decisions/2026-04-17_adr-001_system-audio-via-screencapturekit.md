# ADR-001: Use ScreenCaptureKit For System Audio Capture
## Status
accepted

## Context
The product requires recording everything the user hears from macOS output while staying within Ventura+ platform capabilities and keeping the app local-only.

## Decision
Use `ScreenCaptureKit` to capture system audio, selecting the main display when available and enabling audio capture on the stream configuration.

## Alternatives considered
- CoreAudio loopback drivers: more control, but adds complexity, install friction, and dependency on routing setup.
- Virtual audio device approach: stronger routing flexibility, but outside MVP simplicity goals.

## Consequences
- The app relies on Screen Recording permission for system audio capture.
- Display selection becomes part of system-audio capture behavior.
- Some runtime constraints are defined by `ScreenCaptureKit`, not by the app.

## References
- `docs/01-requirements/2026-04-17_requirements-v1.md`
- `Sources/AudoCaptureCore/Capture/SystemAudioCaptureService.swift`
