# Requirements Compliance Matrix

Last updated: 2026-04-17

Source of truth:

- [Requirements.md](/Users/konstantinfokhtberger/Documents/Codex/AudoCapture/docs/Requirements.md)

This document compares the current implementation against the original MVP requirements so the
project does not lose context over time.

## Overall Status

- Fully aligned areas: architecture split, manual recording flow, separate PCM outputs, MP3 post-processing, metadata persistence, basic UI states, permission UX, single-track fallback policy, graceful termination handling, regression coverage for major failure paths.
- Partially aligned areas: selected input device support on macOS is best effort, exact output folder format.
- Not yet proven areas: real end-to-end audio quality and track-duration alignment on actual hardware/runtime.

## Functional Requirements

### 1. Recording controls

Status: Implemented

- `Start Recording` button exists.
- `Stop Recording` button exists.
- visible states exist: `idle`, `starting`, `recording`, `processing`, `completed`, `failed`
- manual start/stop flow is implemented

Note:

- The extra `starting`, `completed`, and `failed` states are additive and do not conflict with the requirement.

### 2. Audio capture

Status: Partially implemented, with best-effort device selection

Implemented:

- microphone capture via `AVAudioEngine`
- system audio capture via `ScreenCaptureKit`
- both streams are started concurrently
- best effort support for different device sample rates via normalization/conversion
- microphone inventory and selection UI
- selected microphone ID is passed into recording startup

Gap:

- selected microphone support is best effort because `AVAudioEngine` device binding on macOS is constrained
- real behavior still needs manual validation across built-in, USB, and Bluetooth devices

Assessment:

- materially closer to the requirement than default-input-only behavior
- not yet equivalent to a dedicated HAL/AudioUnit routing implementation

### 3. Track formation

Status: Implemented with one explicit design choice

Implemented:

- outputs are separate files: `mic.wav`, `system.wav`
- internal recording is PCM, uncompressed
- sample rate and channel count are normalized explicitly
- metadata now includes track metrics and duration delta diagnostics

Design choice:

- implementation normalizes to:
  - mic: `48 kHz` mono
  - system: `48 kHz` stereo

This fits the requirement because normalization was allowed if it improves stability.

### 4. Saving results

Status: Mostly implemented

Implemented:

- one folder per session
- folder contains PCM originals, MP3 derivatives, and `metadata.json`
- folder opens after post-processing

Deviation:

- requirement examples `/Recordings/YYYY-MM-DD-HHMM/`
- implementation uses `~/Documents/Recordings/YYYY-MM-DD-HHmmss/`

Assessment:

- behavior is correct
- path shape is slightly more specific than requested, but not harmful

### 5. Conversion

Status: Implemented

- conversion happens after `Stop Recording`
- original PCM files are preserved
- target files are `mic.mp3` and `system.mp3`
- failure of one encoder pass is preserved in metadata and does not delete PCM files

### 6. Metadata

Status: Implemented and extended

Implemented:

- recording start timestamp
- recording end timestamp
- duration
- used devices/source descriptions
- sample rate
- channels
- artifact paths
- post-processing status
- errors

Extended:

- per-track frame counts
- per-track estimated durations
- sync diagnostics

## Non-Functional Requirements

### 1. Performance

Status: Architecturally aligned, not fully runtime-proven

Aligned:

- post-processing is outside realtime path
- capture path writes PCM directly
- no realtime MP3 encoding

Not yet proven in repo automation:

- startup under 1 second on real hardware
- absence of audible gaps/dropouts in real meetings

### 2. Reliability

Status: Implemented for graceful termination, with hard-crash limits

Implemented:

- manual stop path is covered
- failed startup cleanup is implemented
- MP3 failure preserves PCM outputs
- stop-time runtime errors are logged and persisted
- graceful app-termination flush is implemented through app lifecycle integration

Remaining limitation:

- hard crashes and abrupt process death still cannot guarantee flush completion

### 3. Audio quality

Status: Partially implemented

Implemented:

- PCM recording without compression
- no intentional signal processing
- format conversion for differing sample rates

Not explicitly implemented:

- clipping detection/prevention metrics
- hardware-level quality verification on real devices

### 4. UX

Status: Implemented for MVP baseline

Implemented:

- minimal single-screen UI
- visible statuses
- visible last error
- actionable permission buttons for opening System Settings

## Technical Architecture Requirements

Status: Implemented

Present modules:

- UI Layer
- Recording Manager
- Mic Capture Module
- System Audio Capture Module
- Audio Sync / Buffer Layer
- File Writer
- MP3 Encoding Module
- Metadata Writer
- Permissions Manager
- Error Handling / Logging

## Error Handling Requirements

### Explicitly handled

- no microphone permission
- no screen recording permission
- file/directory creation error
- MP3 encoding error
- ScreenCaptureKit or AVAudioEngine startup error
- format mismatch / conversion path
- stop-time device failure surfaced as metadata/logged error
- single-track degraded startup with explicit warnings

### Partially handled

- device disconnected during recording
  - error is logged/persisted when it surfaces during stop or stream failure
  - there is no auto-recovery flow

## Acceptance Criteria Check

### Currently satisfied in code structure and tests

- start path initializes both streams
- stop path produces two PCM outputs
- post-processing path targets two MP3 outputs
- metadata contains key session parameters
- permission failures produce clear user-facing errors
- MP3 failure does not discard originals

### Still requires manual runtime verification

- both PCM files play correctly
- both MP3 files play correctly
- durations match within acceptable tolerance on real recordings
- no audible artifacts during a typical meeting session

## Priority Gaps To Close Next

If the goal is strict conformance to `Requirements.md`, the next missing pieces are:

1. Run manual device-matrix validation for built-in, USB, and Bluetooth microphones.
2. Decide whether the session-folder timestamp format should be normalized from seconds to minute precision to match the original example exactly.
