# P6.1 verification — 2026-10-20

Implementation started from fetched `origin/main` commit `c4c8f55b345db53e95878abf8f2c67cce04deecb`. Work uses one feature branch, `codex/p6-1-ar-distance`, in an isolated worktree; the owner's unrelated dirty checkout is preserved.

Environment: Xcode 26.6 (17F113), iPhone 15 Pro Max Simulator, iOS 26.5 (23F77), x86_64. No physical iPhone was installed, uninstalled, reset or used for measurements.

## Core and build checks

- `swift test`: 238 tests, zero failures, one existing opt-in independent XLSX fixture skipped.
- `swift test --filter DistanceMeasurementTests`: all 10 distance tests pass. Fixtures cover independent published/right-triangle distances, unrounded precision, invalid/overflow/zero coordinates, depth back-projection, old/stale/future frames, selection with fresh snapshots, missing surface, brief tracking loss between polls, completion invalidation, retake and pause/resume/close/interruption states.
- The injectable session fixture returns declared test snapshots only; it does not emulate LiDAR or validate real camera/depth acquisition.
- Repeated `python3 scripts/generate_project.py` runs produce identical project/scheme hashes: 54 app source files, 22 unit-test files and 3 UI-test files. `git diff --check` and Info.plist validation pass.
- Simulator `build-for-testing` passes. An additional unsigned generic arm64 iOS compile passed during implementation; it did not deploy to a device.

## Retained initial Xcode run and corrections

The first selected Xcode run completed with 236 unit tests (one opt-in skip, no unit failures), and three UI cases: P6.1 passed, P3.2 and P4.2 failed. Local evidence is retained outside Git in `/tmp/FieldForgeP61Tests.xcresult`, `/tmp/fieldforge-p61-xcode-tests.log` and exported attachments under `/tmp/FieldForgeP61Attachments`.

- P3.2 stopped before opening the distance utility. The test searched for `tectonicPosition` as a TextView. Its retained accessibility tree exposes `tectonicPosition` and `tectonicDescription` as visible **TextField** controls on iOS 26. The two selectors now accept either native text-input role; values and readback assertions remain unchanged. The geological form itself is unchanged.
- P4.2 passed the new distance-sheet open/close check with three draft photos retained. Later, after returning from the existing plan sheet at the top of the form, an offscreen lazy-row count returned zero. The test now reveals the photo rows before asserting the same count/UUIDs. No photo storage or import implementation is changed.

## Final sequential Xcode run

**Passed:** authoritative `xcresulttool get test-results summary` reports **241 total, 240 passed, zero failed, one skipped**. This comprises 238 unit tests (one existing opt-in skip) and all three selected UI cases. P3.2 completed in 1465 s, P4.2 in 666 s, and P6.1 in 117 s. Local final evidence: `/tmp/FieldForgeP61FinalTests.xcresult`, `/tmp/fieldforge-p61-final-tests.log` and `/tmp/fieldforge-p61-final-summary.json`.

The two initial UI failures were resolved by the documented selector/viewport corrections without changing geological or photo application code. No assertion, expected value, scenario or engineering test was removed. Portrait and landscape exit controls are exercised. XCTest's app-window screenshot was cropped in landscape, so the P6.1 screenshot attachment uses `XCUIScreen.main.screenshot()` instead; functional checks are unchanged. The owner then requested wrap-up, so the additional screenshot-only rerun was interrupted; it is not reported as another successful run. The completed 241-test result above remains the authoritative functional verification. Landscape screenshot capture with this final attachment change is not fully verified.

Command (no retries, sequential selected UI regression scenarios):

```sh
xcodebuild -project FieldForge.xcodeproj -scheme FieldForge \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro Max,OS=26.5' \
  -derivedDataPath /tmp/FieldForgeP61FinalDerived \
  -resultBundlePath /tmp/FieldForgeP61FinalTests.xcresult \
  CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO \
  -only-testing:FieldForgeTests \
  -only-testing:FieldForgeUITests/MappingUITests/testP32SetsEvidenceFaultsValidationResetAndOfflineReopen \
  -only-testing:FieldForgeUITests/MappingUITests/testP42DraftPhotosCancelDiscardTwoPointsAndRelaunch \
  -only-testing:FieldForgeUITests/MappingUITests/testP61DistanceUnsupportedClosePreservesMappingDraft test
```

P3.2 checks original readings, all J1–J5 and tectonics through utility dismissal, save and offline reopening. P4.2 checks photo UUIDs, utility dismissal, discard, saved points and relaunch. P6.1 checks unavailable AR without invented results, disabled point selection, retake, both exit actions, picket/X retention, and landscape scrolling/exit. This is a selected UI regression run, not a claim that every existing UI test was executed.

Real LiDAR placement, camera permission denial/regrant, interruptions, background camera release, low-light behavior and physical accuracy still require hardware qualification. Follow the [API/coordinate contract and physical comparison procedure](p6-1-ar-distance.md). No millimetre or survey-accuracy claim follows from these automated results.
