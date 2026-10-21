# Second real-iPhone review: field workflow fixes

Baseline: `main` at `3acbc3e`, merged PR #54. The owner requested focused checks, not complete XCTest/UI regression runs. UI text remains Russian. Mapping schema remains **8**; no migration, reset, file deletion or independent-measurement journal compatibility change is introduced.

## Draft ownership and spatial context

The confirmed data-loss cause was `MappingWorkflow.requestContext`: every selection change reached `applyContext`, which reset the draft, or demanded discard first. A validated excavation-only change now commits just the selected context, preserving the entire value-owned draft and its UUID, field date, text, original measurement UUIDs, interpretations, Q/RMR inputs, source plan, coordinate provenance and photos. Destination validation still requires the excavation's project and horizon membership. Failed writes publish neither the new context nor a modified draft.

Changing project/horizon offers **«Отложить и перейти»** or **«Остаться»**. The workflow parks the draft with its original context and restores it when that project/horizon is revisited, including its previous excavation. No coordinates or source plans are reassigned. Retained photo bytes remain owned by parked draft UUIDs. In-flight photo selection must finish before a spatial-context switch; an excavation-only selection can continue receiving photos for the same draft. This is **in-memory recovery only**: process termination still loses unstaged draft data. The confirmation explicitly states this limit.

Draft photos retain their immutable capture/linkage context, including the excavation selected at import. A pre-first-save photo may therefore retain a different valid excavation on the same project/horizon from the point's final selection. `unknownBeforeFirstSave` remains mandatory and provides no capture coordinates. Saved-point `.pointRevision` photos still require exact point/excavation/revision relationships. No original image, hash, UUID, pending intent or metadata history is rewritten. The photo register already exports capture-context IDs separately from point IDs.

## iPhone measurement incident analysis — device verification outstanding

No owner crash trace, `.ips`, termination reason or physical-device reproduction is available in the repository. Therefore the cause of the reported termination is **not confirmed**, and this change does **not** claim to resolve the physical-device crash.

Confirmed code findings:

- Joint capture presented a measurement sheet from a joint editing sheet and used the same root `AppModel`/`MeasurementAcquisition` as independent measurement and other capture screens. Modal appearances/disappearances could reset or stop another presentation's session. Sensor notifications also invalidated the root view at 20 Hz. These are ownership/lifecycle hazards, not evidence of a particular termination exception.
- Core Motion callbacks already converted samples at the boundary and delivered events through `Task { @MainActor ... }`; a provider generation token filtered callbacks from stopped sessions. Acquisition ignored events after stop/HOLD. `NSMotionUsageDescription` was present. The inspected sensor, orientation and measurement paths had no force unwrap/fatal-error explanation for this incident.
- Joint originals were already staged locally, validated against a copy of the parent draft and published atomically with explicit J-set evidence UUIDs. That behavior is retained.

Mitigations: each `MappingMeasurementSheet` owns a separate capture-only `AppModel`/provider/session, without opening the independent journal. Its own scene phase gates acquisition; close, acceptance and disappearance stop/reset that session. A dead presentation cannot accept a reading. Root/independent lifecycle no longer controls mapping modal acquisition. Joint measurement uses a full-screen cover above the editor, returning to the intact editor on cancel. Point-level requests and geological editors freeze the owner UUID when opened; callbacks verify that UUID and saving state, even if the parent view is recomputed. Core Motion errors invalidate the generation and stop updates; provider teardown stops the manager. Unavailable/denied data remains a recoverable status with retry and close actions, never a fabricated reading/reference.

Remaining investigation: run the checklist below on the owner's iPhone. If termination recurs, collect the exact `.ips`/Jetsam report, device/iOS/build, motion permission state and reproduction sequence; distinguish privacy termination, memory pressure, actor/runtime assertion and presentation failure before claiming a root cause. A simulator build and synthetic lifecycle tests cannot establish physical sensor accuracy or crash resolution.

## Picket convention and historical compatibility

`PicketInput.meters` remains the original metre / kilometre-plus-three-digit-metre parser. Historical validation never guesses a convention from the saved value.

New draft observations, interval endpoints and tectonic pickets use `tenMeters`:

| Entered text | Chainage, m | Normalized display |
| --- | ---: | --- |
| `1` | 10 | ПК 1 |
| `1,7` or `1.7` or `1+7` | 17 | ПК 1+7 |
| `12+9` | 129 | ПК 12+9 |
| `12` | 120 | ПК 12 |
| `12+9,5` or `12+9.5` | 129.5 | ПК 12+9,5 |
| `0,17` | 1.7 | ПК 0+1,7 |

A decimal comma/dot is a fractional **picket**. After `+`, it is a fractional **metre offset**: one integer digit 0–9 followed optionally by a decimal part. Reject `1+10`, `1+07`, `ПК 0+005`, mixed decimal-plus forms, exponent notation, signs and grouping separators for new capture. Optional `ПК` prefix is accepted. No leading-zero metre padding is guessed. Confirmation displays normalized picket and metres; raw entered text remains stored.

Optional Codable tags `MappingObservation.picketConvention` and `MappingPicket.convention` identify new values. A missing tag means `legacyMeters`; existing schema-8 files decode without rewriting. This is an additive current-format contract, **not a migration**. Unknown tags and text/chainage inconsistencies fail closed. Historical observations, interval endpoints, tectonic locations and correction snapshots validate using their recorded convention. Correction editors retain and label the historical convention rather than silently changing it. Notes-only corrections preserve original chainage and prior snapshots. CSV/XLSX continue exporting original text plus full numeric chainage; no export parser reinterprets the text. Old application builds should not be used to write new tagged records.

## Barton Q: numerical calculation versus documented assessment

The [NGI April 2025 handbook](https://www.ngi.no/globalassets/bilder/forskning-og-radgivning/bygg-og-anlegg/q-handbook_2025_english_final.pdf) remains the reference. The published tables/ranges and calculation formula are unchanged. Tables 4–6 were checked again against the official handbook for this iteration. In particular Ja J/M is 8–12, P is 13–20, and Jw E/F have different time-dependent conditions despite sharing the endpoint 0.1. Ja P is never silently assigned 12.

`BartonQInput` has one shared evaluator core with two entry points:

- `evaluate()` retains the exact strict `NGI-Q-2025-04/FieldForge-1` validation for historical stored assessments, including documentation requirements and explicitly stored contact.
- `fieldEvaluation()` calculates when RQD, all five valid coefficients, Jn location and actual adjustment prerequisites are specified. It derives contact only from the explicit Ja category's published contact group and still rejects incompatible Jr/Ja or explicitly conflicting contact. It does not require RQD-source administration, assessment source, range rationale or correction documentation to display the number. These remain available in record details. Missing spacing/reduction for an applied adjustment still blocks calculation.

New assessment snapshots identify `NGI-Q-2025-04/FieldForge-field-2`, and validate against `fieldEvaluation()`. Old method IDs continue validating against the old strict path, including incomplete results. No historical Q snapshot is recalculated or replaced. Exports retain the stored method, input and numerical snapshot. For field-2, `evaluation.missing` describes numerical completeness, not formal documentation. The UI labels numerically valid but undocumented inputs **«Предварительная полевая оценка · документация неполная»**; this does not establish support design or safety.

The main form contains RQD, five coefficient choices, Jn location and Q. Published fixed rows populate their exact number. Range rows start with no number and offer explicit endpoint buttons plus an inline field accepting any valid in-range value; endpoint buttons are convenience controls, not new NGI category mappings or automatic engineering choices. Contact appears next to Ja. Sources, author, range evidence, corrections and optional methodology are behind **«Сведения об оценке»**. Existing metadata and explicit adjustments remain editable. RMR89 remains unchanged and input-only.

## Other field UI changes

- **«Трещиноватость и тектоника»** combines J1–J5 and tectonic structures. Both editors stage values and require explicit acceptance; cancellation leaves parent values intact. Tectonic thickness is optional under **«Дополнительно»** in its editor.
- The standalone Mapping **«Дополнительно»** section is removed. **«Интервал и исходные замеры»** retains interval editing, original evidence and populated-interval visibility. Saved observation details still expose geology and technical provenance.
- Excavation selection uses the same caption/body/44-point selector and contextual plus styling as project/horizon controls, retaining search.
- DXF import proposes one plus the highest existing positive integer revision, including pending imports; first import proposes 1. Legacy nonnumeric identifiers are preserved. Normal import hides the manual override under a disclosure. Input validation rejects nonpositive/noninteger/duplicate identifiers, including numeric aliases such as `01` versus `1`. Registration independently rejects duplicates; identical retry is idempotent. Original DXF files and point/source-plan links remain untouched, and revision numbers imply no geometric compatibility. The viewer drawing behavior is unchanged.
- Coordinate labels show exactly one decimal in Russian formatting. Mapping/correction fields show the full original input when focused and retain that text/value on blur. Details offer full-precision copyable coordinates. No save, DXF interpretation, measurement, calculation or CSV/XLSX path uses the display formatter.
- Repeated Settings and DXF explanations are removed or moved to optional help. Sensor validation, north/CRS uncertainty and approximate measurement warnings remain.

## Verification and owner walkthrough

Executed on 2026-10-21:

- `swift test --scratch-path /private/tmp/fieldforge-second-review-spm --filter ...`: **18 unique focused cases across the final targeted runs, 0 failures**. Cases cover compatible/invalid/failed context changes, suspended return with completed/in-flight photos and unrelated saved-point photo recovery, new/legacy picket persistence and corrections, duplicate DXF revisions, Q numerical/strict historical paths, independently hand-calculated Q cases and complete published table endpoints, HOLD/background/stale/unavailable sensor events, original measurement/J-set ownership and a historical correction.
- `xcodebuild -project FieldForge.xcodeproj -scheme FieldForge -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/fieldforge-second-review-build CODE_SIGNING_ALLOWED=NO build`: **BUILD SUCCEEDED**. Xcode 26.6 (17F113). The only warning is unused App Intents metadata extraction; no AppIntents dependency exists.
- `python3 scripts/generate_project.py` twice: identical project SHA-256 `09d6787f13fd1c1b060835fd057618210da5b342308c451e7aa9faca0c841383`; no inventory/project-file diff.
- `git diff --check`: passed.

Compiler/simulator cache access initially required the normal sandbox escalation; reruns succeeded. No complete regression suite, UI automation suite, signed device build or physical sensor qualification was run. The existing broad UI suites were not used to certify these changed navigation flows. Verification uses temporary directories and synthetic fixtures; no production journal or attachments are opened by tests. Complete XCTest/UI regression suites and physical-device measurements are intentionally not run.

On the real iPhone, without uninstalling/resetting the app:

1. Fill a point before choosing a выработка: picket, date, precise coordinates, notes, J1/J2, Q. Select a valid excavation on the same horizon; verify every field remains and no discard dialog appears. Change excavation again after adding photos.
2. Park the draft by changing horizon/project. Return to its project/horizon; verify the same draft, excavation, source plan, photos and original measurement links. Save it and inspect the photo register. Finish photo selection before changing project/horizon. Keep the app running while testing volatile draft recovery.
3. In each J1–J5 editor, open iPhone measurement, wait, HOLD, cancel, reopen, background/foreground, retry and accept. Cancel must preserve prior editor values. Accept J and save point; inspect immutable original and explicit set link. Repeat with motion denied/unavailable. Capture diagnostics if termination recurs.
4. Enter `1`, `1,7`, `1.7`, `1+7`, `12+9`, `12`, `12+9,5`; check confirmations. Reject `1+07` and `1+10`. Open an existing historical point and make a notes-only correction; verify its recorded metres and interval endpoints remain unchanged.
5. Enter RQD 80, Jn F=9, Jr B=3, Ja C=2, Jw A=1, SRF G=1, ordinary location. Q should be approximately 13.33 immediately without source/author forms, labeled preliminary. Exercise Ja/Jw/SRF ranges and incompatible Jr/Ja contact. No number should be silently selected from a range.
6. Add/edit/cancel a tectonic structure, including optional thickness. Open the interval/originals link and an older populated interval.
7. Import DXFs successively: 1, 2, 3 (or next existing maximum). Try a duplicate override; verify refusal and previous originals/markers remain. Check coordinates show one decimal but full precision is available in editing/details and exports.
