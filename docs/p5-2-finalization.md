# PR #27: controlled Xcode failure investigation

## Reproduction conditions

On 2026-10-20 the ten failures retained in [the initial P5.2 report](p5-2-verification.md) were run independently on unchanged `main` **abc9f2a9ae1858b47bf609619cdebb99932b1b34** and original PR head **47c58bdf0f0f8e79f72d201a4d040b93ba5a7a3d**. Both runs used Xcode **26.6 (17F113)**, Debug / `FieldForge` shared scheme, iPhone 15 Pro **x86_64**, iOS **17.2 (21C62)**, `CODE_SIGNING_ALLOWED=NO`, `-parallel-testing-enabled NO` and `-maximum-concurrent-test-simulator-destinations 1`. Identical `-only-testing` lists selected the ten reported cases. No source edits preceded these runs.

Two new isolated simulators were used: main `D55545BE-4448-49C7-AB4E-163BE0BD249B`, PR `04F21231-600B-4605-92C4-887A0D7FF26B`. Every test uses its existing UUID-based `FIELD_FORGE_TEST_RUN_ID` isolation. Previous `xcodebuild`, `xctest`, app and UI-runner processes were checked before subsequent runs. A process lock covered execution, result flushing and simulator shutdown. Investigation runs never overlapped. The later full run was interrupted at the owner’s request, as recorded below. Xcode sometimes shut its simulator down between the cleanup state check and shutdown command; this harmless post-test cleanup race was checked by re-reading state, not counted as a test failure. Both original runs completed and their result bundles contain **10 tests: 1 passed, 9 failed, 0 skipped**.

Local evidence (outside Git): `/tmp/p27-finalization/baseline.xcresult`, `pr-original.xcresult`, corresponding `.log`, `*-summary.json`, `*-failure-stages.json`, and `accessibility-evidence.json`. The baseline checkout `/private/tmp/fieldforge-p27-main-baseline` remained clean. The owner's unrelated dirty checkout was not edited.

## Every original failure

The UI class prefix is `FieldForgeUITests/`; the unit prefix is `FieldForgeTests/`.

| Test | Unchanged main / original PR | Classification and evidence |
| --- | --- | --- |
| `MappingTests/testCorruptGraphLoadRejectsInvalidForeignKeysAndExtremeTimezoneOffset` | Passed **0.120 s / 0.063 s** | **Runner/simulator interference in the historical attempt.** The old result reports signal TERM and a runner restart, without an assertion failure. Both isolated reproductions pass; the earlier isolated full unit run also passed. No product or unit-test change is justified. |
| `MappingUITests/testP32bRatingsPartialFailureCompleteQResetAndJournalReopen` | Main stops at the picket search; PR stops at `disclosure("Barton Q")` | **UI selector and scroll/timing error.** The original one-direction search can scroll away from the picket immediately after context-menu dismissal. Explicitly returning to the top reaches it. On both unchanged apps the disclosure title is `StaticText`; its chevron is an unlabelled `Button`, so a button-label prefix query never matches. |
| `MappingUITests/testP32SetsEvidenceFaultsValidationResetAndOfflineReopen` | Main stops at the picket search; PR stops at `disclosure("Интервал и положение")` | **Same UI helper errors.** Both app trees contain the interval title as `StaticText` and an unlabelled chevron button. The failure is not missing geological data or a failed save. |
| `MappingUITests/testP33CorrectionHistoryPlanMoveEvidenceAndRelaunch` | Main stops at the picket search; PR stops at `disclosure("Системы трещин")` | **Same UI helper errors.** Both captured trees explicitly contain `StaticText, label: Системы трещин: 0/5`; querying its titled button is incorrect. |
| `MappingUITests/testP3MixedDraftCaptureDismissBackgroundPlanTabsAndAtomicSave` | Both stop after adding the first manual measurement, looking for `Замеры: 1` | **Case-sensitive section-header selector.** Both trees contain `ЗАМЕРЫ: 1`; the measurement was added. The full expected count is retained by a case-insensitive exact comparison. |
| `MappingUITests/testSuccessiveObservationsContextGuardJournalAndRelaunch` | Both find the two journal rows, open the first observation, then fail on the card heading | **Case-sensitive section-header selector.** Both trees expose `НАБЛЮДЕНИЕ · АКТУАЛЬНАЯ ВЕРСИЯ`. The initial report's attribution to a journal row was incorrect; the detailed activity log identifies the following heading assertion. |
| `P2MappingUITests/testOriginalHorizon200ImportProjectionPickingAndMarker` | Both fail only the card-heading assertion | **Same heading selector.** Original DXF parsing, expected projection/counts, XY selection, retained manual Z, save and marker pass before it; subsequent filter/relaunch checks also execute. |
| `P2MappingUITests/testOriginalHorizon300ImportProjectionPickingAndMarker` | Both fail only the card-heading assertion | **Same heading selector**, with the same preceding and subsequent assertions passing for the original 300 fixture. |
| `P2MappingUITests/testOriginalHorizon400ImportProjectionPickingAndMarker` | Both fail only the card-heading assertion | **Same heading selector**, with the same preceding and subsequent assertions passing for the original 400 fixture. |
| `P2MappingUITests/testTwoPlansPickingSavedMarkersOverlapAndDraftRetention` | Both stop at the card heading after opening the saved marker | **Same heading selector.** Import of two versions, photo draft, pan/zoom, proposed coordinates, save and marker-to-observation navigation succeed before that assertion. |

The three group tests do **not** fail at the same first step on main and PR. The distinction above is intentional. An additional identical diagnostic UI bundle independently inspected the unchanged app builds to establish their actual accessibility behavior beyond main's earlier picket-helper failure.

## Independent accessibility evidence

A temporary inspection method created only synthetic context/measurement data, attached `app.debugDescription` at each relevant screen, opened Barton Q by its visible title, saved/reopened the observation, and opened its immutable original measurement. The **same compiled UI bundle** (SHA-256 `6250902708100743adec4015680152529f125b25b93806f524832f5652959590`) ran sequentially against the original main and PR app binaries: **1 passed, 0 failed, 0 skipped each**. Only `UITargetAppPath`, its matching product paths and app environment paths were changed in copied external `.xctestrun` files. No baseline source or app binary was modified. The diagnostic method was removed before submission.

Both trees contain these roles/labels (addresses and frames omitted):

```text
StaticText, label: 'Интервал и положение · необязательно'
Button                         # adjacent chevron, no title label
StaticText, label: 'Системы трещин: 0/5'
StaticText, label: 'Тектоника: 0'
StaticText, label: 'Barton Q'
Button                         # adjacent chevron, no title label
TextView, identifier: 'qRQD', label: 'RQD исходное, %', placeholderValue: 'Не указано'
StaticText, label: 'ЗАМЕРЫ: 1'
StaticText, label: 'НАБЛЮДЕНИЕ · АКТУАЛЬНАЯ ВЕРСИЯ'
StaticText, label: 'ИСХОДНЫЙ РУЧНОЙ ВВОД'
```

Opening Q by the titled `StaticText` reveals `qRQD` on both apps. This also exposes previously masked wrong `TextField` queries: SwiftUI fields declared with `axis: .vertical` are `TextView` here. The rating fields, tectonic description/position and correction reason selectors now use that role; their production declarations are unchanged. Single-line numeric/orientation fields remain `TextField`. The section-heading helper still requires the entire expected label, including counts and punctuation; it only ignores case. It also covers the same presentation of historical/original-measurement section headings reached later in these scenarios.

SHA-256 of unchanged `FieldForge.debug.dylib`, verified before and after diagnostic runs:

- main: `ac42253d30237e425c9043cd39f5293698c51355821062077b6f7a6aae070b72`
- original PR: `2dc0e72a9a0d3ae32666af56f373dd77e1caf4546793fcfeb466955366b7df1a`

The full diagnostic trees and attachments are in `/tmp/p27-finalization/diagnostic-main.xcresult` and `diagnostic-pr.xcresult` (corresponding logs retain the text trees).

## Keyboard input beyond the original selector blockers

The focused corrected-selector run reached deeper steps: Q/RMR passed completely (**308.819 s**), while the sets and correction cases were rejected at save. Exporting **all** attachments (without `--only-failures`, because the hierarchy attachment is not flagged as associated with failure) revealed actual validation alerts: `Тектоника №2: Мощность, м: введите конечное число ≥ 0...` and the corresponding structure №1 error. The saved screen recording shows the latter field containing **`0,`**, although XCTest logged `typeText("0,5")`. This was an incomplete native-keyboard input, not a successful input rejected by the number parser. Bulk Backspace events could likewise leave a prefix behind while inline validation changed the row layout.

A short temporary diagnostic used the same compiled UI bundle against the two unchanged app binaries, comparing five bulk inputs with five inputs sent as separate XCTest actions. Results are deliberately reported separately:

| Immutable app | Bulk `typeText("0,5")` actual values | Separate native actions | Normal save |
| --- | --- | --- | --- |
| main, `numeric-main2.xcresult` | `0,5` in **5/5** attempts | `0,5` in **5/5** attempts | Passed |
| original PR, `numeric-pr3.xcresult` | `0,`, `0`, `0,5`, `0,5`, `0,` (**2/5** complete) | `0,5` in **5/5** attempts | Passed |

Thus the short bulk-input probe did **not** reproduce character loss on main. The relevant form, bindings, validation and parser sources (`MappingGeologyForm.swift`, `MappingGeology.swift`, `MappingModel.swift` and `ManualOrientationInput.swift`) are byte-for-byte identical between the compared commits. The observation supports an **XCTest input/relayout timing problem on this Simulator configuration**, rather than a changed numeric-validation contract. It is not a physical-device typing-speed assessment. The ten original failures are classified independently in the table above; main's earlier selector failures are not presented as proof of a later step having passed.

The helper now sends deletion and all text characters in separate native XCTest actions, allowing quiescence between transient prefixes such as `0,`; it verifies the exact final text before proceeding. It still uses the original characters, including decimal commas, and changes no expected geological values. Keyboard existence is required before typing, with one conditional tap inside the editable text area if the initial normal tap did not open it. No pasteboard, direct model writes, validation bypass, whole-test retry or skipped assertion is used. Exploratory viewport/caret-coordinate changes were rejected after they exposed sheet clipping or keyboard-overlap issues; they are absent from the submitted helper. The temporary diagnostic method was removed.

Local evidence: `selectors-round2.xcresult`, `round2-p32-attachments/BE42B7CC-F428-4F61-808B-8F4726FF649D.txt`, `round2-p33-attachments/9FEB319B-4B83-48D5-BDD9-D13AFBADBB27.txt`, the P3.3 screen recording and `numeric-main2` / `numeric-pr3` logs under `/tmp/p27-finalization`. The shared numeric diagnostic bundle SHA-256 is `4bc49e85b6224bf8a904b786a3705543d4cebd2f365303feaa8daf098cfd0781`.

## Corrections and final verification gate

Corrections are confined to the two existing UI-test files: actual disclosure/text-input roles, exact headings with case-insensitive matching, explicit top-of-form preparation for picket entry, and keyboard readiness before typing (with one conditional leading-text-area tap if the keyboard did not open). A failed form lookup retains its accessibility tree, and a missing save confirmation reports the actual app hierarchy. Text input and clearing wait between native actions, with exact text readback. All **14 existing UI test methods** remain; no scenario, data assertion or expected engineering value is removed or skipped. App code, XLSX, storage, mapping schema, measurement journal, geometry, DXF, photo handling, bundle ID and signing settings are unchanged by this finalization.

The complete Swift run with the fixture enabled passed **228 tests, 0 failures, 0 skips**. Two project generations produced identical project/scheme SHA-256 values (**51 app sources, 21 unit-test files, 3 UI-test files**). The new Swift-generated workbook again passed the independent zipfile/ElementTree/openpyxl validator (**22 package parts, 15 sheets, 307 typed data cells**).

Run **both complete Xcode unit and UI targets** sequentially on the final published PR head. The final command must have no `-only-testing`, `-skip-testing`, retry-until-success or parallel test execution. Enable the existing opt-in synthetic XLSX fixture through a writable test-container path, so it is exercised in the final suite rather than skipped. Record authoritative `xcresulttool get test-results summary` totals and the tested head in PR #27's description. Keep Draft until that run passes or each remaining blocker is independently shown to predate the PR. Preserve the historical failing results above.

## Owner-requested wrap-up

The full sequential Xcode run on published head `e762c58f150ec02933538f05200c9a0d3ac99e75` passed **228 unit tests, 0 failures, 0 skips**. Before interruption, **7 UI tests completed: 6 passed and 1 failed**; the eighth scenario was still running. These are completed-case counts, not a complete-suite success. Q/RMR, correction/history/relaunch, mixed draft, three-photo and both standalone measurement scenarios passed.

The remaining completed failure was `testP32SetsEvidenceFaultsValidationResetAndOfflineReopen`: exact input readback caught `Сбе` instead of `След разлома без замера` in the multiline tectonic description. The helper had serialized numeric characters but still batched prose. The final correction sends every text character as a separate native XCTest action, retaining exact readback and every scenario/assertion. This correction has **not received a complete UI rerun**.

The owner requested wrap-up while `testP42DraftPhotosCancelDiscardTwoPointsAndRelaunch` was running. The long run was stopped with SIGINT; interruption/runner errors after that point are cancellation evidence, not classified as product failures. No replacement full cycle was started. The final published head therefore has **no completed full unit + UI verification**. PR #27 remains **Draft and not ready to merge**. A future complete sequential run is still required; this report does not claim that the final input correction resolves the remaining scenario.
