# P4.1 verification

Base: fresh `origin/main` at `9257fe5` (merge PR #20). Feature branch: `codex/p4-1-observation-photos`. Scope: first stage of Issue #9; parent stays open.

## Owner follow-up: live camera retry and one current mapping schema

The owner authorized publishing this follow-up to the existing PR #21 with the verification limits below. No new PR is created. These changes are not qualified by the original submission’s passing test counts.

- `MappingModel.importPhoto` now allocates operation identity before I/O and retains exact received bytes/context through intent/staging failure (and a busy writer). Ordinary `retryPhoto` reuses the pair, with no file or second shutter. The byte fallback is released only after the original is verified on disk. Intent/original recovery survives journal failure; a fully completed repeat verifies the existing pair/original without another photo.
- Five `PhotoImportModelTests` exercise this application path in both SPM and Xcode: camera-only UIImage/JPEG, actual staging-destination failure after intent, lost volatile state in a new model, context correction/project switch, normal live retry, intent creation failure, journal failure/restart, busy writer, thumbnail failure and successful cleanup. No claim is made that unwritten memory survives process termination.
- Mapping accepts only schema 7, without upgrades or legacy decode defaults. Migration tests were replaced with current-format reopen/previous-snapshot/round-trip and safe old/corrupt-file refusal checks while retaining their geology, evidence, revision, DXF, relationship and storage-failure assertions. Existing backups remain untouched. The independent measurement journal and its compatibility code/tests are unchanged. See [owner policy](../AGENTS.md).
- Deterministic generation repeated successfully: 45 app sources, 18 unit files, 3 UI files. Project SHA-256 `923bc54b8e7c5d1542f060a599cf3b200fc2e86657f5a2c8dec5d96a7d15fba4`; scheme `0c8384ee590d062f08c9155992aecf3b83131733e8a9fa4852918a3fe74c372b`. `git diff --check` passed.
- Compilation/test discovery of the final local source succeeded inside the workspace sandbox: **195 discovered tests**, not 195 passing executions. Command used temporary compiler/SPM caches and `swift test list --disable-sandbox` (only SPM's nested subprocess sandbox is disabled; the tool's outer workspace sandbox remains).
- An earlier complete restricted-environment SPM run, before the fifth new test, executed **194 tests, 19 failures**. Photo validation failed because system type conformance was unavailable in that environment: an independent diagnostic returned `UTType.jpeg.conforms(to: .image) == false` and no JPEG MIME type. Production validation was not weakened. This is not a passing full run and does not qualify the new retry tests.
- Normal full `swift test` and the requested full sequential Simulator unit/UI run have **not started**: automatic permission review repeatedly failed with `Selected model is at capacity`; the tool explicitly says this is review-service failure, not an unsafe-action determination. Normal checks still need repeating after service recovery; fix actual failures and record complete-run and targeted-repeat results separately. After initially choosing to wait, the owner explicitly requested updating the existing PR with these limits. An attempted hourly follow-up could not be created either: the automation tool returned the same permission-review capacity error. No automatic retry is scheduled; resume this chat after service recovery.

Current reproduction after permission service recovery:

```sh
swift test
python3 scripts/generate_project.py
/usr/bin/caffeinate -i -s xcodebuild -project FieldForge.xcodeproj -scheme FieldForge \
  -destination 'platform=iOS Simulator,id=6B663914-DE0B-49E4-AA93-43FE0B7BAAB0' \
  -derivedDataPath /tmp/fieldforge-p41-revision-derived \
  -resultBundlePath /tmp/FieldForge-P41-Revision-Full.xcresult \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
```

## Original PR submission checks (before this owner follow-up)

The sections below are a historical report for the initial PR commit `86d9255`. Its mapping-migration claims are superseded by the current-schema-only owner decision. Its passing counts do not qualify the changed code above.

## Automated coverage

`P41PhotoTests` adds 18 tests, runnable via both SPM and the Xcode unit target:

- Three distinct images on one fully unlocated/no-DXF point; same source filename but unique UUID paths, individual names/numbers/capture dates, exact received bytes/hash/format/dimensions, file-journal reopen.
- Unknown capture time versus separate import instant, including camera images with no timestamp; timezone-less EXIF remains wall-time text. Camera metadata and EXIF subseconds are retained. Provider conversion limitation retained.
- Exact version-2 point/location reference survives version-3 location correction and project selection change while import is pending; other project has no leaked record.
- Failure injection after intent, staging write, original promotion and thumbnail generation; reconstructed file service/workflow retries with unchanged IDs and no duplicates. Journal commit failure retains no partial published photo/attachment relationship.
- Actual filesystem failure writing the journal backup; source bytes unchanged and pending operation preserved. Failed intent path creation and malformed pending manifest preserve staged evidence.
- Missing and same-size hash-corrupt originals are explicit read failures, including when a thumbnail exists; records survive. Thumbnails regenerate and do not copy source GPS dictionaries (the fixture original actually contains synthetic GPS); mine coordinates stay unknown and actual format comes from bytes despite a wrong filename extension. Wrong replacement bytes are rejected.
- Photo metadata revisions preserve initial values; stale/empty-reason edits fail. Cross-project/dangling attachments, old headers hiding photo data and missing schema-7 tables fail closed.
- Schema-6 fixture migration preserves exact original bytes and P3.3 history; conflicting `.p6-backup` blocks writes without changing source. File store prevents removing photo originals or correction history.
- Original P3.3 observation, raw sensor/manual measurements and full correction history encode to exactly the same bytes before/after photo addition and metadata correction.

UI coverage includes three deterministic generated PNG images through the real model/staging/journal path, per-photo metadata revisions, zoom, UUID retention and names after relaunch, no artificial geological revision, camera-unavailable message and system Photos cancellation. The fixture transport is DEBUG + Simulator + `--ui-testing` only, analogous to existing DXF fixture controls; it does not verify real Photos provider downloads or camera hardware. The existing DXF marker scenario also checks the shared card's photo actions.

## Runs

- Full `swift test`: **190 passed**, zero failures/skips (172 prior tests + 18 photo tests).
- Deterministic `python3 scripts/generate_project.py`: run twice; generated project and scheme SHA-256 match. Source inventory: 44 app files, 17 unit files, 3 UI files.
- Xcode 26.6, iOS 17.2 Simulator unit target: **190 passed**, zero failures/skips. UI phase of that early run was interrupted to use final UI changes.
- First P4.1 iOS 26.5 UI run exposed a presentation-host issue with the Photos dialog attached to a List Section. The stable content container now owns presentation. The initial failed attempt is not counted as a passing check.
- Targeted P4.1 iOS 26.5 UI repeat: **1 passed**, zero failures/skips; 382.411 seconds. Three metadata edits, three pinch zooms, source UUIDs/names after relaunch and original geological version 1 verified. The second attempt had tapped a partially exposed preview underneath the navigation bar; test scrolling now checks its center against navigation/tab bars. Inspected the exported zoom screenshot. This passing run preceded the final EXIF-only camera-time refinement and explicit UI clearing of nominal Z; final complete run includes both.
- A complete parallel run (three Xcode Simulator workers) was attempted and stopped after platform UI failures: `kAXErrorServerNotFound`, lost keyboard focus, timed-out snapshots and inability to terminate the app. Failures included the unchanged standalone measurement/export scenarios. This run is **not** a passing regression; final verification is repeated sequentially below.
- Complete sequential iOS 26.5 Simulator regression: **190 unit tests passed; UI 7 passed / 5 failed** (8 assertions). The run took 18,419 seconds. P3.2 ratings, P3.2 geology, P3 mixed acquisition, P3.3 correction/history/relaunch, successive mapping observations and both standalone measurement/export scenarios passed. P4.1 failed in the existing context-creation helper before reaching photo import; the log jumps from 26.77 to 1825.41 seconds during a 10-second existence wait. The three original P2 scenarios timed out while synthesizing UI events. The two-plan scenario had Files-picker/element assertions, including the new photo-section scroll assertion corrected below. This is **not** a passing full UI regression. Result bundle: `/tmp/FieldForge-P41-Serial-Final.xcresult`.
- Separate sequential repeat on iPhone 17 Pro/iOS 26.5, final production code: **P4.1 UI passed**, 370.076 seconds. This includes explicitly cleared nominal Z, camera EXIF-time refinement, three photos/metadata/zoom/relaunch, and geological version 1. **All three original DXF scenarios passed**: +200 m 269.835 s, +300 m 264.875 s, +400 m 259.793 s. The two-plan scenario exposed a mistake in the new test assertion: it scrolled toward the top while the photo section was below the viewport. A Simulator screenshot confirmed the card at the top. This repeat was stopped (Xcode cancellation hung; own process terminated) and the test's scroll direction corrected; it is not counted as a completed five-test pass. Logs: `/tmp/fieldforge-p41-ui-retry.log`; incomplete bundle: `/tmp/FieldForge-P41-FailedUI-Retry.xcresult`.
- Corrected two-plan/marker scenario: **1 passed**, zero failures/skips, 382.925 seconds. This verifies the photo actions in the card opened from a saved marker, two overlapping saved points, plan-version isolation and relaunch. Result bundle: `/tmp/FieldForge-P41-Marker-Final.xcresult`. These repeats kept the Mac awake only for the command duration using `caffeinate -i -s`; no system power setting changed.

Final coverage: 190 SPM tests and 190 final iOS Simulator unit tests passed. All 12 UI scenarios have a passing execution across the complete run and targeted repeats. There is **no claim of a single clean full UI run**: the complete sequential run failed five scenarios, subsequently repeated successfully; the new marker-scroll test error was corrected and verified separately. Real image-provider success/permission cases and physical camera behavior remain the owner checks below.

No physical iPhone installation, data reset, signing/bundle/icon change or automatic merge was performed. Build products, simulator journals, screenshots, temporary images and xcresults remain outside the repository.

## Reproduction

```sh
swift test
python3 scripts/generate_project.py
/usr/bin/caffeinate -i -s xcodebuild -project FieldForge.xcodeproj -scheme FieldForge \
  -destination 'platform=iOS Simulator,id=9213E94D-6540-434F-AD58-074C439F967B' \
  -derivedDataPath /tmp/fieldforge-p41-derived \
  -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO test
```

Project/scheme SHA-256 after repeated deterministic generation: `bc11f28f9a38e4663156583b25d1f088827ff3db2ea8e82c6e2a53c36001ca13` / `0c8384ee590d062f08c9155992aecf3b83131733e8a9fa4852918a3fe74c372b`.

## Owner manual checks (not claimed as completed)

On the owner's chosen device/build, separately verify real camera permission denial/re-enable, cancel, shutter, orientation, received representation and capture-time availability and provenance. Verify multiple real Photos (including HEIC/orientation and library/cloud permission/provider failures) and Files selections, cancellation/denied security scope and third-party File Provider behavior. Confirm originals remain available offline after disconnecting/relauching. SPM/model failure injection is not a physical disk-full or camera reliability qualification.

Review the [storage/recovery and complete backup composition](p4-1-photos.md) before copying/restoring field data. No ZIP/XLSX package generator or automated attachment restore is implemented. A JSON-only copy is not a complete backup; missing originals must be reported.
