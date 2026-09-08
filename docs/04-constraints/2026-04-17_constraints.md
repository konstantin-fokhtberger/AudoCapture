# Constraints
## Platform Constraints
- Supported OS target is macOS Ventura or newer.
- System audio capture depends on `ScreenCaptureKit` availability and permission flow.
- The app is desktop-only and local-only.

## Technical Constraints
- Microphone capture uses `AVAudioEngine`, which offers only best-effort direct input-device routing on macOS.
- System audio capture is display-scoped through `ScreenCaptureKit`; the selected display affects capture behavior.
- MP3 creation depends on external tools available in `PATH` or `FFMPEG_PATH`.
- MP3 encoder subprocesses are bounded by an implementation timeout and are terminated on cancellation.
- Realtime code should avoid expensive work beyond conversion and file writes.

## Legal / OS Restrictions
- Microphone access requires explicit user consent.
- System audio capture requires Screen Recording permission and may require app restart depending on macOS behavior.
- The app cannot bypass system privacy controls.

## Known Limitations
- Hardware validation for built-in, USB, and Bluetooth microphones is still mostly manual.
- The app does not yet expose output-device selection or system-audio source selection beyond display policy.
- Hard termination or power loss cannot guarantee buffer flush.
- Sync diagnostics are observational; they do not provide sample-accurate clock alignment.
- Permission recovery may still require the user to restart the app after changing macOS Screen Recording settings, depending on OS behavior.
- MP3 timeout duration is fixed in code for MVP and is not user-configurable.
