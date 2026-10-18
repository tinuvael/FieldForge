# P3.3 verification — 2026-10-18

## Environment

New branch `codex/p3-3-observation-revisions` created from freshly fetched `origin/main` at `d2ba21a` (merged PR #18). Xcode 26.6 (`17F113`), iOS 26.5 Simulator, iPhone 17 Pro Max (`9213E94D-6540-434F-AD58-074C439F967B`). Simulator builds use `CODE_SIGNING_ALLOWED=NO`; UI tests use independent UUID namespaces. No physical app install, uninstall, reset or device journal access.

## Checks

- Targeted Swift: **18 P33RevisionTests passed, 0 failures**.
- Complete Swift: **172 passed, 0 failures**, covering all existing P1–P3 tests, published Q examples, unchanged sensor/manual geometry/HOLD and original DXF fixtures.
- Initial targeted Xcode run: **13 unit tests passed** (before four additional edge-case tests were added). The new UI scenario reached saved-point editing and dirty Cancel, then failed expecting the Cancel-role button in a native confirmationDialog popover; iOS 26 hides that action in this popover presentation. The editor now uses an explicit alert with both Continue Editing and Discard. No saved data was lost.
- Targeted Simulator repeat: **17 unit + 1 UI test passed, 0 failures**. The UI scenario completed in 476.286 s and passed the full correction/history/plan/relaunch path. Result: `/tmp/FieldForge-P33-Targeted-Final.xcresult`.
- Complete Simulator regression: **171 unit + 11 UI tests passed, 0 failures, 0 skipped**; `xcresulttool` confirms 182 total. UI suite duration 3723.802 s; P3.3 passed in 482.343 s, full J1–J5/tectonic regression in 1022.022 s, Q/RMR in 519.341 s, real DXF horizons 200/300/400 in 241.896 / 232.091 / 237.202 s and two-plan overlap/draft retention in 298.208 s. Result: `/tmp/FieldForge-P33-Complete.xcresult`.
- Final hardened-source Simulator check: **172 unit + 1 P3.3 UI test passed, 0 failures**. This reruns every unit test after the schema-header/joint-identity protections, and the entire correction/plan/history/relaunch UI path after Russian source-label cleanup and stricter version 2/3 badge assertions. P3.3 UI duration: 463.716 s. Result: `/tmp/FieldForge-P33-Final.xcresult`. Other UI scenarios were unchanged by these final model guards and passed in the complete regression run above.
- Deterministic project generation repeated with identical project/scheme SHA-256: `267d7edf4773d5af04c0a891df0c4665dd93d497da935f8dc249a617f4de5589` / `0c8384ee590d062f08c9155992aecf3b83131733e8a9fa4852918a3fe74c372b`. Inventory: 37 app source files, 16 unit-test files, 3 UI-test files. Signing, bundle identifier, icon, Phase 1 geometry and DXF parser are unchanged.

Review also added regression coverage for a corrupted old schema header that must not discard a present revision table, and for reusing a withdrawn joint UUID with contradictory local-version content. Both cases were reproduced before hardening; final Swift tests pass. The complete Simulator regression run started before these final model guards; a final all-unit plus P3.3 UI run checks the hardened source, including explicit version-badge assertions and Russian source labels.

The first full Swift run exposed two existing DXF isolation assertions after widening overlay lookup for the correction picker. The normal selected-horizon restriction was restored as the default, with an explicit frozen-plan scope only for corrections. The complete rerun passed; no regression assertions were relaxed.

## Coverage

`P33RevisionTests` covers J1 orientation/fault-thickness correction with reason and author; structurally/encoded unchanged multiple manual and physical-source-shaped sensor originals; preserved J2 timestamps/links; sequential revisions, predecessors and undo by append; partial/unknown tectonics and interval removal; source Q recalculation against independent `40/3` and `10` examples and unchanged historical assessments; input-only RMR; invalid numeric/rating/interval/evidence corrections; missing reason; simulated write failure and actual backup-write I/O failure/retry; stale editor rejection; append-only store protection for original/revision contents; disk relaunch/reopen; exact schema-5 backups including a literal historic-offset/unknown-location record; backup conflicts and corrupt/missing revision graphs; real DXF-backed XY movement, exact version/units/provenance and one marker; switching drawing versions and manual XY override without conversion; preserving an unrelated capture draft and original point ownership.

The P3.3 UI test uses normal project/point/manual evidence/J1/fault/DXF creation. It checks prefill, Cancel warning, required-reason error and retained draft, corrected J1/fault and plan position, comparison/history/original read-only detail, two sequential corrections, same point UUID after relaunch and one marker. Existing UI scenarios retain their original checks with only the detail section label updated for effective-version wording.

## Reproduction

```sh
swift test --filter P33RevisionTests
swift test
python3 scripts/generate_project.py
xcodebuild -project FieldForge.xcodeproj -scheme FieldForge \
  -destination 'platform=iOS Simulator,id=9213E94D-6540-434F-AD58-074C439F967B' \
  -derivedDataPath /tmp/FieldForge-P33 CODE_SIGNING_ALLOWED=NO test
```

Local logs/result bundles remain under `/tmp/fieldforge-p33-*` and `/tmp/FieldForge-P33-*`, outside version control. Temporary test screenshots and synthetic simulator journals are not shipped.

## Limits

Drafts remain in memory and cannot survive process termination before save. Raw measurement additions/removals/reassignment and project/horizon/excavation reassignment are deliberately unavailable. Plan coordinate-frame metadata is corrected by selecting an explicitly imported plan revision, not by rewriting the old frame. RMR89 is uncalculated. Large-history performance, multi-process concurrency, disk-full/power-loss durability and physical measurement accuracy are not qualified. Schema 6 requires this or a newer reader; exact migration backups support reviewed recovery, not automatic downgrade. No mechanical/wedge capability is added.
