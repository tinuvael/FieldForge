# P2 verification — 2026-10-16

Branch: `feature/p2-dxf-horizon-plans`, based on fetched `origin/main` at `1d31ad2` (merged P1). The initial working tree was clean. No physical iPhone app installation, removal/reset, production device journal access, bundle-ID or Personal Team changes were performed.

## Executed core checks

- `swift test --scratch-path /tmp/fieldforge-p2-spm`: **101 tests, 0 failures**, macOS / Xcode Swift toolchain.
- `python3 scripts/generate_project.py`: 25 app source files, 9 unit-test files, 3 UI-test files. Two consecutive runs produced identical project/scheme hashes.
- `git diff --check`: passed.

New cases cover signed/decimal elevations, finite extreme-value round trips, unknown legacy horizon names, nominal Z vs manual override/clear, context guards, success reset, failed-save state preservation and immutable elevation/datum snapshots. A literal P1 mapping fixture verifies UUID/value preservation, unchanged original coordinate/chainage metadata, exact immutable backup bytes, idempotent reopen and migration backup failure/conflict protection. Existing Phase 1/2 migration, manual entry, sensor geometry/HOLD, CSV, corruption and atomic-persistence tests remain included.

DXF tests use hand-authored ASCII fixtures and independent literal control vertices/cardinal arc coordinates. They cover all five supported entity families (POLYLINE includes VERTEX/SEQEND), CCW wraparound arcs, known inverse viewport coordinates after pan/zoom/window-aspect changes, large coordinate precision, off/frozen layers and paper-space exclusion, corrupt/binary/unsupported inputs, non-default OCS, bulges, multiple imports/revisions, same-length hash corruption, missing/changed files, pending import recovery, exact plan/project/horizon/excavation isolation, overlapping points, retained draft values/Z, manually edited drawing units and partial coordinates.

## Simulator and visual checks

Target: **iPhone 15 Pro Max**, simulator UUID `BD08E87B-C0C8-4B44-AB68-BA35A4F3174D`, **iOS 26.5**, **Xcode 26.6 (17F113)**. An iOS 17.2 runtime is also installed; it is not the reported execution target.

**Final complete simulator run: 105 tests passed, 0 failures, 0 skipped**: 101 core XCTest cases and all 4 UI tests. `xcresulttool get test-results summary` confirms `Passed` and the counts. The final Xcode session completed successfully in about 13 minutes.

```sh
xcodebuild -project FieldForge.xcodeproj -scheme FieldForge \
  -destination 'platform=iOS Simulator,id=BD08E87B-C0C8-4B44-AB68-BA35A4F3174D' \
  -derivedDataPath /tmp/fieldforge-p2-serialized -parallel-testing-enabled NO \
  -resultBundlePath /tmp/fieldforge-p2-acceptance.xcresult \
  CODE_SIGNING_ALLOWED=NO test
```

UI coverage includes manual compass save/journal/relaunch/CSV, simulator HOLD/save/relaunch/CSV, P1 successive observations/context guards/project isolation, and P2 two-plan import, real Files-picker open/cancel, XY after pan/zoom, retained manual Z/picket, save/reset, marker-to-journal navigation, revision isolation, overlapping-point selection and relaunch. The standalone P2 acceptance run also passed before the final complete run.

Local final evidence: `/tmp/fieldforge-p2-acceptance.xcresult`, `/tmp/fieldforge-p2-acceptance.log`, `/tmp/fieldforge-p2-summary.json`, `/tmp/fieldforge-p2-spm.log`. Results are actual executions, not static inspection.

Visual QA inspected the proposed point, saved journal detail and overlapping-point chooser. Local screenshots are retained at `/tmp/fieldforge-p2-verified-evidence/plan-proposed.png`, `saved-point.png` and `overlapping-points.png`; build/result artifacts are not committed.

Development UI runs exposed and fixed stale first-sheet selection state and missing close navigation from a point detail. The acceptance scenario exercises both fixes. Full reruns also updated test scrolling/keyboard handling; failed intermediate runs are not reported as passing final verification. Xcode emitted AppIntents metadata-extraction/no-debugger-version messages and signed XCTest-framework stripping warnings; these are toolchain diagnostics, not source compilation failures.

The UI DXF fixture inputs are simulator-only DEBUG controls gated by `--ui-testing` and launch environment; they exercise normal plan setup, original-file staging, integrity validation and graph commit. Production Files selection remains the native security-scoped/coordinated importer. The UI suite opens/cancels the real system Files picker; importing from a real Files provider is **not** covered by that fixture route. UI-test mapping stores use UUID namespaces so reruns do not require resetting existing journals.

## Limits

- Simulator/mock acquisition and software regressions do not verify physical Core Motion accuracy or device upgrade reliability. No physical phone was modified.
- Files/iCloud/provider downloads, physical storage-full/power-loss behavior, large real mine drawings and engineering survey accuracy remain unqualified.
- DXF is a bounded 2D display adapter, not complete CAD. BLOCK/INSERT, bulge curves and other unsupported entities are warned/skipped; source-plan overlays deliberately exclude manual/other-revision coordinates. See [full supported subset and recovery contract](p2-dxf.md).
- JSON repository and Canvas are bounded prototype-scale services. SQLite, CAD preprocessing for larger plans, cross-plan coordinate registration, PDF/raster georeferencing and a portable backup/restore UI remain separate work. A complete recovery copy must include managed originals and operation manifests beside JSON; no JSON-only backup claim.
