# P3.1 verification — 2026-10-17

Branch `feature/p3a-mapping-measurements`, based on fetched `origin/main` at `f316934`. Scope is the P3.1 portion of Issue #8 plus the owner's subsequent request to integrate the new root icon. The root PNG remains untouched; a byte-identical authoritative copy is included under `branding/`. No physical iPhone installation, uninstallation, reset or record access was performed. Bundle identifier, signing configuration, geological orientation algorithms and DXF implementation are unchanged. The icon is replaced only with the supplied artwork; see [asset preparation](../branding/README.md).

## Results

| Check | Result |
| --- | --- |
| Targeted Swift mapping/manual/automatic/P3 tests | 64 passed, 0 failures |
| Complete `swift test` | 119 passed, 0 failures |
| Xcode P3 unit tests, iPhone 15 Pro Max / iOS 26.5 | 10 passed, 0 failures |
| Targeted P3 UI scenario, same simulator | 1 passed, 0 failures |
| Complete Xcode unit/UI suite | 119 unit + 7 UI passed; 1 UI case failed (126/127 cases; 2 setup assertions in that one case) |
| Isolated rerun of failed horizon-300 UI case, final icon build | 1 passed, 0 failures |
| Separate final simulator build with new icon | Passed; built bundle ID and AppIcon reference verified |
| New owner icon, master copy and repeated asset generation | Byte-identical master; deterministic 1024×1024 opaque RGB export |
| `python3 scripts/generate_project.py` repeated with SHA-256 comparison | Deterministic project and shared scheme |
| `git diff --check` | Passed |

Toolchain: Xcode 26.6 (17F113). Simulator UUID: `BD08E87B-C0C8-4B44-AB68-BA35A4F3174D`. Xcode commands use `CODE_SIGNING_ALLOWED=NO` on the simulator only; project signing settings are preserved. Initial sandbox cache/CoreSimulator access restrictions were resolved by running the checks with the required access.

The initial new test build exposed an ambiguous Foundation/domain `Measurement` test type and helper-name mistakes; corrected before successful checks. Initial UI assertions failed because fast whole-screen swipes skipped lazy Form rows and because original manual text was offscreen. Video inspection confirmed both originals remained in the point; the test now scrolls the Form itself and locates original text explicitly. The final targeted UI run completed successfully with no retries of the test within that run. Its HOLD screenshot was inspected: circular plane schematic, downhill arrow, both large labeled values, source/north/quality and controls are simultaneously legible.

## Full simulator run and isolated rerun

The full Xcode command completed all 119 unit tests and all eight UI cases. Seven UI cases passed, including integrated P3 capture and the existing standalone workflows, consecutive points, original DXF horizons 200/400 and two-plan/overlapping-marker retention. The horizon-300 case failed during excavation setup: the editor did not appear after an automated tap, causing two assertions in that one case. The trace contains a greater-than-seven-minute automation gap immediately before that tap; the captured hierarchy still showed the valid project/horizon and main form. This gap is an observation, not proof of the failure's cause.

The unchanged horizon-300 test was then run alone against the final application build with the new icon. It passed end-to-end (1/1), including setup, original DXF import, point selection/save, marker reopening, relaunch and journal filtering. No application logic or test changes were made to obtain that pass. This is **not a zero-failure full-suite result**; retain the initial setup failure as a simulator-automation verification limitation. The full run spanned a user interruption, so elapsed test durations are not performance measurements.

The new icon was integrated while the original full run was already executing its compiled binary. A separate final simulator build and the subsequent isolated UI rerun compiled the new asset successfully. The generated master/AppIcon were visually inspected, and the built 120px icon was inspected as well. Original artwork remains intact.

## Coverage

- Manual decimal-comma input, original text, grid/unknown north and original timestamp; source-specific validation remains shared with the standalone workflow.
- Automatic complete HOLD snapshot, raw Core Motion diagnostics, timestamp, north and quality; invalid, moving, stale/future and unavailable readings cannot HOLD. Inclination-only capture retains an absent azimuth.
- One provider, stop on HOLD/background/dismissal/manual mode; ignore late stopped events, invalidate live readings on return, retain held evidence during temporary backgrounding, restart cleanly on retake.
- Multiple mixed originals stay unpersisted until point save; draft removal is local. Invalid, duplicate, orphaned, missing or multiply owned UUIDs reject the whole graph.
- Point-level atomic save, independently timestamped originals, retained context and nominal horizon Z, cleared per-point fields/date/measurement list; a following point has independent identity and no inherited originals.
- Validation, injected storage failure and changed-file failure retain the full draft and previous in-memory graph. Saved original edits are rejected.
- Measurement-only dirty drafts guard changes of project, horizon and excavation; cancellation preserves evidence.
- P1 literal fixtures and a P2 graph with managed original DXF/marker upgrade without loss, exact source backup bytes, and successful reopening. Corrupt v3 evidence-table absence fails closed.
- UI: manual + simulated automatic originals on one point, HOLD/background/add, cancelled sheet, DXF navigation, tabs, context cancellation, empty isolated standalone journal, point save/reset, original manual detail and journal reopening after relaunch.

## Commands and local evidence

```sh
swift test --filter 'P3MeasurementTests|MappingTests|MeasurementTests|ManualMeasurementTests'
swift test
python3 scripts/generate_project.py
xcodebuild test -project FieldForge.xcodeproj -scheme FieldForge \
  -destination 'platform=iOS Simulator,id=BD08E87B-C0C8-4B44-AB68-BA35A4F3174D' \
  -derivedDataPath /tmp/FieldForge-P3-DerivedData \
  -resultBundlePath /tmp/FieldForge-P3-Full.xcresult CODE_SIGNING_ALLOWED=NO
```

Local logs: `/tmp/fieldforge-p3-horizon300-rerun.log` (isolated pass), `/tmp/fieldforge-p3-icon-build.log` (final asset build), `/tmp/fieldforge-p3-targeted-v2.log`, `/tmp/fieldforge-p3-swift-full.log`, `/tmp/fieldforge-p3-xcode-targeted-v3.log` (10 P3 unit passes; UI scrolling failure), `/tmp/fieldforge-p3-xcode-targeted-v4.log` (final targeted UI pass), `/tmp/fieldforge-p3-xcode-full.log`. Final targeted UI bundle: `/tmp/FieldForge-P3-Targeted-v4.xcresult`. Full and isolated bundles: `/tmp/FieldForge-P3-Full.xcresult`, `/tmp/FieldForge-P3-Horizon300-Rerun.xcresult`. Results and generated build artifacts are not committed.

## Limits

Simulator/mock tests do not validate physical geological accuracy, magnetic interference behavior or physical screen/fixture contact. Independent compass comparison remains required. Storage failure checks use injected errors and an external-file-change fixture, not physical disk-full/power-loss testing. Drafts survive navigation and temporary backgrounding in memory, not process termination. Mapping export, representative sets, Q/RMR, faults, photos and new DXF features remain outside this PR.
