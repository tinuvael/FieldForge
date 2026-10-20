# P5.2 verification

The initial runs below are retained as historical evidence. The controlled `main`/PR comparison, individual failure classifications and UI-test corrections are documented in [PR #27 finalization](p5-2-finalization.md). The PR description records the final complete Simulator run against the published head.

Base: fetched `origin/main` at `abc9f2a` (merged PR #26 / P5.1). One new feature branch `codex/p5-2-xlsx` in an isolated managed worktree. The owner's dirty original checkout is preserved. Current main already uses mapping schema 8; this PR changes no schema, migration, journal, measurement, sensor, geometry, DXF, signing, icon or bundle identifier. No physical iPhone installation or data reset.

## Automated runs

- Targeted `P52_EXPORT_FIXTURE_DIR=/tmp/fieldforge-p52-validation swift test --filter 'Mapping(CSV|XLSX)ExportTests'`: **23 passed, 0 failed, 0 skipped** (11 existing CSV + 12 XLSX), including the synthetic fixture.
- Complete `swift test`: **227 passed, 0 failed, 1 skipped** (228 discovered). The skip is the opt-in XLSX fixture writer when its environment path is absent; that test passed in the targeted run.
- `python3 scripts/generate_project.py` twice: **51 app sources, 21 unit-test files, 3 UI-test files**. Project/shared-scheme SHA-256 values match across generations. Inventory is committed. `git diff --check` passes.
- Complete Xcode 26.6 / iPhone 15 Pro / iOS 17.2 Simulator run (`xcodebuild ... CODE_SIGNING_ALLOWED=NO test`): **231 passed, 10 failed, 1 skipped (242 total)**, authoritative `xcresulttool get test-results summary` result. Bundle: `/tmp/p52-final-simulator.xcresult`. The app and both test targets build. UI results are **5 passed, 9 failed, 0 skipped**. The full result also retains **one unit-test TERM failure** during runner restart, so its unit status is 226 passed, 1 failed, 1 skipped. A later console pass does not erase that recorded failure.
- Isolated complete Xcode unit confirmation (`test-without-building -only-testing:FieldForgeTests`), after all previous runners exited: **227 passed, 0 failed, 1 skipped (228 total)**. Bundle: `/tmp/p52-unit-confirm.xcresult`. This checks the full unit suite without the restart interference; it does not replace or conceal the failed full-run result.
- Independent iPhone 15 / iOS 17.2 export UI (`test-without-building -only-testing:FieldForgeUITests/MappingUITests/testP51MappingCSVPreviewShareCancelAndDraftRetention`): **1 passed, 0 failed, 0 skipped**. Bundle: `/tmp/p52-export-smoke.xcresult`. The same export test also **passed in the full iPhone 15 Pro run**. It switches CSV to Excel on the frozen preview, dismisses/repeats native sharing and verifies next-draft retention. Exported screenshots were visually inspected: one **Office Spreadsheet** with **Сохранить в Файлы**, plus explicit timezone, inclusive dates, format picker and point count in preview.

### Full-run failures and scope

- `MappingTests/testCorruptGraphLoadRejectsInvalidForeignKeysAndExtremeTimezoneOffset()`: Test crashed with signal term.
- `P2MappingUITests/testOriginalHorizon200ImportProjectionPickingAndMarker()`: XCTAssertTrue failed
- `P2MappingUITests/testOriginalHorizon300ImportProjectionPickingAndMarker()`: XCTAssertTrue failed
- `P2MappingUITests/testOriginalHorizon400ImportProjectionPickingAndMarker()`: XCTAssertTrue failed
- `MappingUITests/testP3MixedDraftCaptureDismissBackgroundPlanTabsAndAtomicSave()`: XCTAssertTrue failed
- `MappingUITests/testP32bRatingsPartialFailureCompleteQResetAndJournalReopen()`: failed - Element not visible: Button (First Match)
- `MappingUITests/testP32SetsEvidenceFaultsValidationResetAndOfflineReopen()`: failed - Element not visible: Button (First Match)
- `MappingUITests/testP33CorrectionHistoryPlanMoveEvidenceAndRelaunch()`: failed - Element not visible: Button (First Match)
- `MappingUITests/testSuccessiveObservationsContextGuardJournalAndRelaunch()`: XCTAssertTrue failed
- `P2MappingUITests/testTwoPlansPickingSavedMarkersOverlapAndDraftRetention()`: XCTAssertTrue failed

The three disclosure failures occur in existing ratings/sets/correction scenarios. Other mapping failures are existing UI assertions for the measurement-count text and observation-card section heading (the successive-observations test had already found both journal rows); all four plan scenarios fail the static-text assertion for the saved observation-card title. These scenarios do not exercise XLSX. At the time of this initial run their detailed root causes were unresolved, and no baseline comparison on `main` had been completed. The PR was kept in Draft. See the subsequent controlled comparison linked above; this historical result is not replaced by a later passing run.

An earlier diagnostic full attempt was interrupted after repeated picket scroll-selector failures. The restart overlapped shutdown of its predecessor, and the subsequent full result recorded one unit test terminated with TERM. The isolated confirmation above resolves unit verification without rewriting that history. A small test-only helper change returns picket searches to the top of the form after context selection; it changes no app behavior or assertions.

The 12 XLSX tests independently read ZIP central-directory records/descriptors, parse every XML part and compare every emitted data-sheet cell against its typed frozen source. Coverage includes independent projects/date periods, optional scopes, empty sheets, DST boundaries, one corrected current point, multiple original measurements/evidence links, long decimal coordinates/orientation text, complete/partial/unknown faults, stored Q and incomplete Q/input-only RMR, plan/version/units/parent metadata, historical photo context and unknown capture time/location, missing original files, Russian multiline/quoted/formula-like text, original apostrophes, control/escape handling, nulls, oversized-text rejection, cancellation before/during writes, partial disk failure, retry, owned-file cleanup and frozen snapshots after source edits. Existing CSV byte-contract/selection tests remain unchanged.

## Independent XLSX validation

The Swift fixture contains synthetic data only and is not committed. `scripts/validate_mapping_xlsx.py` uses Python `zipfile`, ElementTree and **openpyxl 3.1.5** (read-only validation, no workbook authoring and no application dependency). Result: **PASS** for ZIP CRCs, **22 XML/relationship parts**, **15 sheets**, **307 typed data cells** matched against the fixture's expected values/types, canonical headers, row counts, all represented UUID joins, sheet/package targets and content-type overrides, styles, frozen panes, filters, alternating rows, blanks, formula safety and exact decimal text. There are no formula/macro/external-workbook parts. X is exactly the string `-123.12345678912345`; the photo name is the literal `=1+1`, without a CSV apostrophe or executable formula. This is structural/reader interoperability, not formal exhaustive ISO schema certification.

Reproduce with the fixture environment above and `python3 scripts/validate_mapping_xlsx.py /tmp/fieldforge-p52-validation` in a Python environment with openpyxl.

## Actual desktop spreadsheet application

Numbers Creator Studio successfully opened the generated `.xlsx`. AppleScript read **all 15 sheet names**, `Сводка!B2 = FieldForge-Mapping-XLSX/1`, exact `points!T2 = -123.12345678912345`, literal `photos!I2 = =1+1` with **no formula**, blank `photos!Q2` capture timestamp, and original `measurements!M2 = 360`.

Numbers imports data into its own tables and may add empty rows (the one-point sheet became ten table rows). Its imported `points` table reports zero semantic header rows even though OOXML freeze panes are verified independently. Thus Numbers import is not evidence that its table headers/filter UI exactly reproduce Excel's frozen row behavior. Microsoft Excel is not installed; no actual Excel UI testing is claimed. Additional Numbers reads confirmed X has AppleScript `text` type and chainage has `real` type, the header uses `Calibri-Bold` with a dark fill, first-column width is 234 pt and header height is 36 pt. Russian multiline photo notes and the original decimal-comma dip text `45,125` were preserved. All 15 imported table dimensions were queried; Numbers pads small tables to at least ten rows/five columns. This is actual application-level readback, not a full visual/interaction acceptance test.

## Limitations

Analysis workbook only: no originals, DXF bytes, complete history, backup/restore or original-file integrity scan. The frozen dataset remains in memory, while ZIP content streams to disk without a full-workbook buffer. ZIP32/Excel row/column/text limits fail clearly without truncating source data. Large JSON/notes may require CSV instead. High-precision cells intentionally remain text and need deliberate high-precision parsing downstream. No physical-device accuracy test, native iPad acceptance, external share-extension completion, actual Files destination write/reopen, full Dynamic Type/VoiceOver matrix, or actual Excel compatibility check is claimed.
