# P4.2 verification

Base: freshly fetched `origin/main` at `42693d8` (PR #21 merged). Branch: `codex/p4-2-draft-photos`. Work uses an isolated managed worktree; the original checkout's uncommitted P4.1 changes are preserved. Schema 8 was explicitly approved by the owner in this chat for the required location-basis field. Issue #22 is part of #9; parent #9 stays open.

## Automated coverage

Ten `P42DraftPhotoTests` run through the shared `MappingModel`, real managed image storage and isolated temporary file journals:

- Three distinct camera-only images before the first Save, no DXF/known XYZ, no published graph or disk writes before Save, validation failure retention, one complete graph on reopen and unchanged original measurements/history.
- Actual staging-destination failure after intent creation, exact retained camera bytes without an external file, same photo/attachment/point UUIDs on ordinary retry, and queued Save after success as a no-op.
- Actual journal `.previous` write failure after original promotion, no partial point/photo/measurement graph, complete draft retention, disk-backed retry and refusal to invent a point from a draft intent after restart.
- Photos alone as a dirty change, cancel/discard/context switch, active-session Save refusal, late callback after discard and after successful Save, independent successive points and clear form with retained context/nominal Z.
- Draft capture location stays explicitly unknown after XY edits; no geological revisions are created. Saved photo evidence remains in its project when another project receives its own point/photos.
- Removal after failed Save retains staged/promoted files and saved originals. Thumbnail failure after commit is recoverable without another point/photo. Intent-creation filesystem failure retains camera bytes.
- A controlled concurrent edit during a suspended disk write is detected without losing the photo or field edit; context changes are locked until Save finishes.
- Picker cancellation leaves a clean form; missing required capture-location basis fails decoding. Existing current-format/safe-refusal tests cover schema 8 and preservation/refusal of schemas 1–7.

All previous P3.3 evidence/correction-history, P4.1 saved-photo and five camera-byte/retry model tests remain in the full suite. Independent measurement migration tests are unchanged.

Simulator UI coverage adds three generated images to the draft through the real validation/Save/storage path. It checks preview, Photos/Files cancellation, unavailable-camera handling, photos-only discard/cancel, plan return, two successive saves with distinct UUIDs, journal/relaunch persistence, project isolation and explicit unknown capture location. The existing two-plan/marker scenario now receives three photos before its first Save and checks their UUIDs from the saved marker, including after relaunch. Fixture injection is DEBUG + Simulator + `--ui-testing` only; it does not claim real provider download or hardware-camera success.

## Executions

- Complete final `swift test`: **205 passed**, zero failures/skips. Log `/tmp/fieldforge-p42-spm-complete.log`. Earlier corrected complete run: 203 passed before two additional tests were added.
- The first complete development SPM run executed 203 tests with 21 failures: 19 correction/history failures exposed random IDs when reconstructing correction forms, fixed by using the saved observation UUID; two new-test expectations were corrected (explicitly cleared Z retains a provenance object with nil XYZ, and the fixture horizon is +393 m). Compilation-only failures before this run are not counted as executions.
- Deterministic project generation ran twice with identical output: 47 app sources, 19 unit files, 3 UI files. Project SHA-256 `b8bfedc8a8ffa555265528d2b594dbd0a0aaf321103c2def9375a8ff5694479a`; scheme `0c8384ee590d062f08c9155992aecf3b83131733e8a9fa4852918a3fe74c372b`. `git diff --check` passed.
- Xcode 26.6, iPhone 17 Pro / iOS 26.5 Simulator, completed sequential full run: **203 unit tests passed; UI 7 passed / 6 failed**, no skips. UI execution took 2536.556 seconds. This is not a passing full regression. The full binary preceded the two extra unit tests, an additional post-relaunch marker assertion and per-photo memory/disk status label.
- Failures: manual-reading diagnostic row was below the visible List area; geology evidence toggle used a partly obscured tap; P3.3 aborted inside UIKit focus-container enumeration (crash report retained); saved-photo camera alert was intercepted by the newly added root-level photo alert; the new draft test reselected the current project and exposed unnecessary horizon/excavation clearing; the marker test read offscreen coordinates after returning to the scrolled draft. Photo alerts now belong to the active draft section, unchanged context selection is ignored before clearing child context, and tests ensure tap/read positions are visible. No measurement/geometry/storage logic was changed to hide these failures.
- Final repeat is running all **205** Simulator unit tests plus these six UI scenarios, using `/tmp/FieldForge-P42-Repeat.xcresult` and `/tmp/fieldforge-p42-repeat.log`. It includes final draft status labels and the post-relaunch marker/photo assertions. Results will replace this pending statement before final delivery.
- An earlier Simulator build stopped on test-source compile errors; the first full attempt was interrupted after the SPM regression was found and is not a passing execution. Its partial bundle is `/tmp/FieldForge-P42-Full.xcresult`. The completed full run uses `/tmp/FieldForge-P42-Final.xcresult` and `/tmp/fieldforge-p42-final.log`.

## Reproduction

```sh
swift test
python3 scripts/generate_project.py
/usr/bin/caffeinate -i -s xcodebuild -project FieldForge.xcodeproj -scheme FieldForge \
  -destination 'platform=iOS Simulator,id=6B663914-DE0B-49E4-AA93-43FE0B7BAAB0' \
  -derivedDataPath /tmp/fieldforge-p42-derived \
  -resultBundlePath /tmp/FieldForge-P42-Final.xcresult \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
```

Use a new result-bundle path when repeating. Build products, isolated Simulator journals, generated test images, logs and xcresults remain outside Git. `caffeinate` applies only for the command duration; no system power setting changes.

## Physical camera and provider limits

No physical iPhone was accessed, installed, reset or modified. Real camera permission denial/re-enable, shutter/cancel/orientation, memory pressure/termination, Photos HEIC/cloud downloads, security-scoped Files and third-party provider failures still require owner device qualification under #24. Model filesystem failure injection is not a physical disk-full/reliability claim. Simulator fixtures verify application ownership and persistence, not provider delivery or physical measurement accuracy.

The unsaved form is not autosaved or recovered after termination. Unwritten camera bytes are volatile; written originals/intents survive without reconstructing the lost form. Never delete these files or infer a missing point. See [contract and backup limits](p4-2-draft-photos.md).
