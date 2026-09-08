# Second Review Pass

Date: 2026-04-17

## Purpose

This review pass re-read:

- product requirements
- current implementation
- existing project docs

The goal was to check whether the current code still matches the documented claims and the MVP
requirements.

## Findings

### 1. Capture startup is sequential, not concurrent

Severity: High

Files:

- `Sources/AudoCaptureCore/Recording/RecordingManager.swift`
- `docs/COMPLIANCE.md`
- `docs/ANALYSIS.md`

What was found:

- `RecordingManager.startRecording()` starts microphone capture first and only then starts
  system capture.
- The requirements explicitly call for simultaneous start with minimal skew.
- `docs/COMPLIANCE.md` currently says both streams are started concurrently, which is no longer
  true for the current implementation.

Why it matters:

- sequential startup increases the chance of measurable start skew between tracks
- the implementation is currently weaker than the docs claim
- sync diagnostics help observe drift after the fact, but they do not replace a better startup
  strategy

Recommendation:

- change startup back to concurrent orchestration
- preserve the current single-track fallback policy while doing so
- update the docs only after the code path is actually concurrent again

### 2. `postProcessingStatus` is incorrect for successful single-track sessions

Severity: High

Files:

- `Sources/AudoCaptureCore/Recording/RecordingManager.swift`
- `docs/COMPLIANCE.md`

What was found:

- when startup degrades to one active track, `stopRecording()` still computes
  `postProcessingStatus` using the fixed tuple `(micMP3URL != nil, systemMP3URL != nil)`
- as a result, a valid system-only session can be marked as `partialFailure` even if its only
  active track encoded successfully

Why it matters:

- this makes `metadata.json` lie about the session outcome
- downstream tooling or future UI based on `postProcessingStatus` will treat a successful
  degraded session as a failure

Recommendation:

- addressed in a later remediation step
- keep post-processing status evaluated against active tracks only

### 3. Documentation has drifted from the implementation

Severity: Medium

Files:

- `docs/ANALYSIS.md`
- `docs/COMPLIANCE.md`
- `docs/RISK_CLOSURE.md`

What was found:

- `docs/ANALYSIS.md` contains duplicated and stale validation language (`3 tests passed` and
  `14 tests passed`)
- `docs/COMPLIANCE.md` says both streams are started concurrently, which does not match the code
- parts of the “risk closure” narrative overstate what is fully closed versus what is still
  partially implemented or only observed via diagnostics

Why it matters:

- these docs are intended to preserve engineering context
- once they drift, they become dangerous because future changes will rely on them as if they
  were accurate

Recommendation:

- treat the docs as status reports, not permanence claims
- refresh the compliance language after every behavior-changing recording-flow update
- keep validation sections factual and single-source, with one current test count and one current
  command recipe

### 4. Microphone device-name lookup still compiles with an unsafe CoreAudio pointer warning

Severity: Medium

Files:

- `Sources/AudoCaptureCore/Capture/MicrophoneDeviceCatalog.swift`

What was found:

- the current `AudioObjectGetPropertyData` call passes `&name` where `name` is a `CFString`
- Swift emits a warning that this forms an `UnsafeMutableRawPointer` to a type that may contain
  an object reference

Why it matters:

- this is low-level CoreAudio interop code
- warnings in this area should be treated seriously because incorrect pointer ownership can
  become a crash or memory-management bug later

Recommendation:

- rewrite the property read using the proper Core Foundation ownership pattern for
  `AudioObjectGetPropertyData`
- keep the code warning-free under the full Xcode toolchain

## Recommendations Ordered By Priority

1. Fix `postProcessingStatus` for one-track sessions and add a regression test.
2. Restore truly concurrent startup for mic/system capture, while keeping degraded fallback.
3. Fix the CoreAudio CFString property read in `MicrophoneDeviceCatalog` so the build is
   warning-free in the device-enumeration path.
4. Reconcile `ANALYSIS.md`, `COMPLIANCE.md`, and `RISK_CLOSURE.md` with the current code after
   the behavior fixes land.

## Notes

This review pass did not treat platform limitations as bugs when they are explicitly acknowledged
 by Apple API constraints. The findings above are about avoidable product/code/documentation gaps.
