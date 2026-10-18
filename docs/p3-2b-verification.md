# P3.2b verification — 2026-10-18

## Environment

New feature branch `feature/p3-2b-rock-mass-ratings` from merged PR #17 / `origin/main` at `1daf11d`. Xcode 26.6 (`17F113`), iOS 26.5 Simulator, iPhone 17 Pro Max (`9213E94D-6540-434F-AD58-074C439F967B`). Builds use `CODE_SIGNING_ALLOWED=NO`. Simulator UI tests use generated test-run UUID namespaces; no physical iPhone installation or data access.

## Verified checks

- Final targeted `swift test --filter P32RatingsTests`: **17 passed, 0 failures**.
- Final complete `swift test`: **154 passed, 0 failures**, including all existing geometry, manual/sensor measurements, DXF, persistence/migration, geology and query tests.
- Xcode Simulator targeted tests: **17 unit + 1 new UI scenario passed, 0 failures**. The UI case completed in 463.753 s and covers table-based Q entry, the RQD floor, invalid RMR save/draft retention, successful reset/context/Z retention, a second point and journal reopening after app relaunch.
- Initial complete Simulator run: **154 unit tests passed; 9 of 10 UI tests passed**, including the new Q/RMR scenario (457.595 s). The existing P3.2a geology UI case failed waiting for the save alert. Its failure hierarchy showed the save row at y=870.7…958.7 while the tab bar began at y=873 (the collection view extended behind it): `isHittable` accepted a partially exposed row, but its tap center was covered by the tab bar. The shared UI save helper now requires the tap center inside the form viewport and above the tab bar, and scrolls there before tapping. Application persistence and geological data code needed no change for this test failure.
- Final complete Xcode Simulator build/test repeat: **154 unit + 10 UI tests passed, 0 failures**. The complete UI suite finished in 3568.519 s. Q/RMR passed in 563.142 s; the corrected P3.2a scenario passed in 1132.913 s, including all J1–J5 evidence and full/partial/unknown tectonic orientations reopened after relaunch. All original manual/sensor, successive-point/context, DXF horizons 200/300/400 and two-plan/overlap/draft-retention scenarios also passed. Final result: `/tmp/FieldForge-P32b-Complete-Final.xcresult`.
- Deterministic `python3 scripts/generate_project.py`: repeated generation preserves project and scheme hashes; 34 app sources, 15 unit-test files, 3 UI-test files. No signing, bundle identifier, icon, Core Motion geometry or DXF parser changes.

Project SHA-256: `8b7621605ce6498cdfcde31b84fdfbd8c72b8fda75feb59202c5ee5b686428df`; scheme SHA-256: `0c8384ee590d062f08c9155992aecf3b83131733e8a9fa4852918a3fe74c372b`.

The engineering inputs, primary-source verification, exact table values, boundary conventions, independent rational-arithmetic examples and RMR89 verification gate are recorded in [P3.2b methodology](p3-2b-ratings.md). Tests cover the RQD floor without overwriting original values, finite positive coefficients and denominators, manual row/range constraints and rationale, all contact combinations, explicit Jn/Jr/SRF corrections and misuse, seven-class transitions at next-representable numbers, out-of-chart results, input provenance and precision, partial assessments, atomic failure/retry/reset, ratings-only context guards, append-only records, exact schema-4 backups, rich historical geology/evidence preservation, corrupt inputs/results/methods and offline disk reopening.

## Reproduction

```sh
swift test --filter P32RatingsTests
swift test
python3 scripts/generate_project.py
xcodebuild -project FieldForge.xcodeproj -scheme FieldForge \
  -destination 'platform=iOS Simulator,id=9213E94D-6540-434F-AD58-074C439F967B' \
  -derivedDataPath /tmp/FieldForge-P32b \
  -resultBundlePath /tmp/FieldForge-P32b-Complete-Final.xcresult \
  CODE_SIGNING_ALLOWED=NO test
```

Local logs: `/tmp/fieldforge-p32b-targeted-final.log`, `/tmp/fieldforge-p32b-swift-final.log`, initial `/tmp/fieldforge-p32b-xcode-complete.log`, final `/tmp/fieldforge-p32b-xcode-complete-final.log`; simulator result bundles/logs contain test evidence and screenshots. Intermediate interrupted/diagnostic runs are not counted as complete suite passes. Temporary logs, downloaded methodological PDF, screenshots and build artifacts are not committed.

## Limits

RMR89 is an input-only, uncalculated assessment because complete original tables/special cases/orientation adjustments could not be qualified. Q is classification only, with no support design, safety factor or stability verdict. Hand-calculated fixtures validate numerical software behavior; they are not site validation or independent professional certification. Physical measurement accuracy, native iPad qualification, power-loss/disk-full trials and revision-based correction editing remain outside this verification. Drafts are in memory, not recoverable after process termination. Old app versions cannot read schema 5. Existing standalone CSV does not export mapping assessments or constitute a complete offline backup.
