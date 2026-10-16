# P1 verification — 2026-10-16

## Environment and safety

- macOS local development, Xcode 26.6 (17F113), Swift Package Manager and iOS 26.5 Simulator.
- Simulator: iPhone 15 Pro Max, `BD08E87B-C0C8-4B44-AB68-BA35A4F3174D`.
- Latest fetched `origin/main` at start: `f89771d`; feature branch `feature/p1-projects-mapping-journal`.
- No physical iPhone install, uninstall, reset or journal access. Bundle ID remains `com.tinuvael.FieldForge`.
- Pre-existing local project/patch preserved in temporary storage; personal Team retained in ignored `Config/LocalSigning.xcconfig`, never included in the commit.
- UI tests use isolated `ui-testing.json` and `ui-testing-mapping.json`; legacy fixtures are synthetic.

## Core checks

`swift test --scratch-path /private/tmp/FieldForge-P1-SPM`: **86 XCTest tests passed**, zero failures. This includes 15 mapping tests, 13 migration tests, and all existing geometry, sensor/manual, CSV and HOLD checks. Relevant coverage:

- Independent projects, project-only filtering, filtered horizons/excavations, multi-horizon identity, editable names/elevation.
- Persisted context, two consecutive point saves, unique IDs, full coordinates/provenance and historical observed date preservation.
- Separate observed/created/updated instants and original timezone; reset of the whole implemented draft after commit with retained context.
- Validation, backup/I/O and external-file-change failures preserve draft/context and original bytes.
- Unsaved context switches at every level, date-only drafts, cancel/discard, failed context persistence.
- Relaunch round trip, previous-snapshot backup, unsupported/corrupt schemas, dangling/duplicate relationships, extreme timezone-offset input, incomplete records.
- Immutable saved observations; byte-for-byte legacy v1/v2 journal and backup preservation when mapping operates.
- Legacy sensor validation across libm numerical noise while rejecting changed status and 1e-8 perturbations; original values remain unchanged.

`python3 scripts/generate_project.py` run twice: identical SHA-256 for project and shared scheme. `plutil -lint FieldForge.xcodeproj/project.pbxproj` and `git diff --check` passed. Resolved `xcodebuild -showBuildSettings -json` confirmed the original local Team, bundle identifier and iPhone device family after regeneration (the Team value is not published). Generated inventory: 22 app source files, 7 unit-test files, 2 UI-test files.

## Xcode checks

Initial and final standalone Simulator **builds succeeded**. First full `xcodebuild test` passed all then-compiled 83 unit tests and both legacy UI workflows. The new mapping UI test failed because the system confirmation popover hid the cancel button; it was replaced by an explicit alert with both cancel/discard actions. The final full rerun passed **86 unit tests + 3 UI tests (89 total), zero failures** on the final source state. UI tests exercised standalone manual and automatic HOLD/save/relaunch/CSV, plus context creation, invalid picket preservation, explicit cancel/discard, successive `ПК 0+005` / `ПК 0+010`, preserved selectors, journal details/relaunch and second-project isolation. A separate attempted focused run ended before tests started when the Simulator stopped and the runner lost XPC; restarting the Simulator without clearing data allowed the full rerun to complete.

The finalized xcresult summary reports `Passed`, 89 passed, 0 failed, 0 skipped.

Final full result bundle: `/private/tmp/FieldForge-P1-final.xcresult`. Logs: `/private/tmp/fieldforge-p1-final-tests.log`, `/private/tmp/fieldforge-p1-swift.log`. Build artifacts and test data remain outside Git. Earlier toolchain output included AppIntents metadata-extraction and signed XCTest-framework stripping warnings; no Swift source compiler warning was observed. Xcode also logged a non-fatal debugger-version lookup error during UI launches; it did not prevent the successful tests.

UI evidence includes mapping capture/details and legacy measurement/journal/share-sheet screenshots in the xcresult attachments. Visual inspection on iPhone 15 Pro Max prompted persistent text labels for all three context selectors and an unclipped chainage-description label.

## Commands

```sh
swift test --scratch-path /private/tmp/FieldForge-P1-SPM
python3 scripts/generate_project.py
xcodebuild -project FieldForge.xcodeproj -scheme FieldForge \
  -destination 'platform=iOS Simulator,id=BD08E87B-C0C8-4B44-AB68-BA35A4F3174D' \
  -derivedDataPath /private/tmp/FieldForge-P1-Xcode CODE_SIGNING_ALLOWED=NO build
xcodebuild -project FieldForge.xcodeproj -scheme FieldForge \
  -destination 'platform=iOS Simulator,id=BD08E87B-C0C8-4B44-AB68-BA35A4F3174D' \
  -derivedDataPath /private/tmp/FieldForge-P1-Xcode CODE_SIGNING_ALLOWED=NO test
```

## Limits

No physical measurement accuracy/upgrade, real disk-full/power-loss or native iPad qualification is claimed. JSON remains a small-journal whole-file store without cross-process locking; the rolling previous snapshot is not a complete export/backup facility. Drafts are in memory, not recoverable after process termination. Mapping capture/linking of original measurements is deferred to Issue #8; coordinates remain manual. No DXF, ratings, wedge mechanics, LiDAR, photo storage or XLSX implementation. Observations are view-only; revision-based correction is future work.
