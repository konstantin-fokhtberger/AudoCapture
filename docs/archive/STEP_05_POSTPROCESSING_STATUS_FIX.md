# Step 05. Post-Processing Status Fix

Date: 2026-04-17

Related review finding:

- [REVIEW_2026-04-17_SECOND_PASS.md](/Users/konstantinfokhtberger/Documents/Codex/AudoCapture/docs/REVIEW_2026-04-17_SECOND_PASS.md)

## Goal

Fix `postProcessingStatus` so it reflects the tracks that were actually active in the session,
instead of assuming both `mic` and `system` were always active.

## Problem

Before this step:

- a successful system-only session could still be marked `partialFailure`
- a successful mic-only session could still be marked `partialFailure`

That made `metadata.json` semantically inaccurate for degraded startup sessions.

## Change

`RecordingManager.stopRecording()` now computes `postProcessingStatus` against:

- `activeTrackKinds`
- `encodedTrackKinds`

Rules:

- all active tracks encoded -> `completed`
- no active tracks encoded -> `failed`
- some but not all active tracks encoded -> `partialFailure`

## Tests Added / Updated

- `startRecordingFallsBackToSystemOnlyWhenMicrophoneFails`
- `startRecordingFallsBackToMicrophoneOnlyWhenSystemFails`
- `oneTrackEncodeFailureMarksSingleTrackSessionAsFailed`

## Validation

After the change:

- `swift build` passed
- `swift test` passed
- `swift run AudoCaptureSmokeChecks` passed

Current automated total:

- 16 tests passed
