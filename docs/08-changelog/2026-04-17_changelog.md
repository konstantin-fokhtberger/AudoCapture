# Changelog
## 2026-04-29
- Added: code review and test report at `docs/07-reports/2026-04-29_code-review-and-test-results.md`.
- Added: requirements Version 1.1 for the 2026-04-29 remediation scope.
- Added: remediation report at `docs/07-reports/2026-04-29_recommendation-remediation-report.md`.
- Changed: testing documentation now records the latest automated validation command results.
- Changed: `RecordingManager` now performs per-track permission fallback and concurrent startup for permitted tracks.
- Changed: inactive failed-startup PCM artifacts are cleaned up before metadata can omit them.
- Changed: `ProcessMP3Encoder` now times out and terminates stalled encoder subprocesses.
- Fixed: CoreAudio microphone device-name lookup no longer emits the previous Swift `CFString` pointer warning.
- Fixed: tests now cover permission-denied fallback, inactive artifact cleanup, and concurrent startup orchestration.

## 2026-04-17
- Added: structured documentation tree under `docs/00-overview` through `docs/09-logs`.
- Added: versioned requirements, architecture overview, constraints, implementation notes, testing strategy, status report, and three ADR files.
- Changed: active project documentation now points to the structured tree instead of ad hoc top-level markdown files.
- Fixed: documentation storage now follows the artifact storage rules more closely.
- Changed: legacy markdown reports and step notes were moved to `docs/archive/`.
