# Third iPhone field review

This successor to merged PR #55 keeps schema 8, offline evidence, source-plan links and the existing engineering calculations. No mapping migration or reset is introduced. Earlier review descriptions are historical where they conflict with this contract.

## Editor ownership and measurement acceptance

Code inspection confirmed that `MappingJointSetsSection` presented `editing` / `editingTectonic` with `.sheet(item:)` but read the owner from a separate `@State editorOwnerID`. That state was written in the button action without being read in the presenting body. SwiftUI could evaluate the presentation closure with an earlier owner value (including nil), while supplying the new sheet item. The resulting guard could reject the original, still-current Mapping draft. This is an implementation-level explanation for the false ownership error; no physical-device trace was available to prove the exact scheduling on the owner's iPhone.

Both editors are presented by one geology modal at the stable Mapping root, outside the lazy Form/Section lifetime. Each presents a single immutable `MappingEditorRequest`: presentation UUID, original draft UUID, frozen context, initial field draft and original-reading snapshot. The sheet and callback consume that exact request. `MappingWorkflow.acceptJointSet` and `acceptTectonic` validate the owner UUID, context, pending transition and saving state. They validate a copied draft (including links and uniqueness) and publish once. No guard was removed and no source reading is assigned without explicit acceptance. Validation failure leaves both collections untouched. Cancellation and retaking stay local to the editor; a new presentation gets a new identity. The Foundation representative adapter retains full precision and north/conventional-side meaning.

Before: add J → measure → accept → editor with technical evidence controls → a possible false owner error. After: add J → measure → explicitly accept as J → selected orientation (at most one decimal displayed) → accept → observation Save. Spacing, persistence, aperture, roughness, infill and notes remain optional. Original readings remain immutable evidence; editing representative values does not edit their readings. A recovery-only action can keep an unusable representative's independently savable reading. DEMO north remains ineligible for a geological representative.

The combined geology section retains tectonics. The default editor shows type, orientation, north, thickness and optional description. Historical per-structure picket/position remains under a collapsed separate-position editor. The ordinary Mapping form has no interval/original-measurement navigation row; saved details retain originals, and the correction editor retains specialized interval controls. Independent measurement-journal behavior is unchanged.

## Pickets

New ten-metre-convention observations store canonical Russian labels and the corresponding unrounded numeric chainage. Parsing and normalization use Foundation `Decimal`; binary conversion happens only after decimal normalization. Comma and dot decimal pickets, optional `ПК`, and explicit single-digit metre offsets are accepted:

| Input | Metres | Label |
| --- | ---: | --- |
| `1` | 10 | `ПК 1` |
| `1,7` | 17 | `ПК 1+7` |
| `12+9` | 129 | `ПК 12+9` |
| `12,18`, `12.18`, `12+1,8` | 121.8 | `ПК 12+1,8` |

A zero offset is omitted. Offsets ≥10, padded offsets, negative/ambiguous/malformed input are refused. New decimal input is limited to 28 total digits and chainage below 10^15 m to avoid Decimal overflow or silent decimal truncation. The journal, observation details, plan markers/callouts, photo context and wedge source summaries use the same convention-aware display. Corrections show canonical confirmation.

Absent convention tags retain the original metre/km+metre parser, including padded legacy offsets. Historical ten-metre entries may contain the former binary product (`Double(text) * 10`); validation accepts that exact historical result as well as the decimal result. An unchanged picket in any correction retains its exact original text and chainage. Unrelated note corrections never silently normalize history. Existing interval and per-structure pickets keep their convention and meaning. Originals remain append-only.

## Q presentation

`FieldQCategory` is the owner's custom FieldForge simplification, dated 2026-10-21. It is a derived presentation and is never persisted into Q calculation snapshots:

- Q < 1: «Весьма неустойчивые породы».
- 1 ≤ Q < 4: «Неустойчивые породы».
- 4 ≤ Q ≤ 10: «Средней устойчивости».
- Q > 10: «Устойчивые породы».

The calculated Q domain remains positive; the presentation helper also handles zero, and refuses negative/nonfinite input. Q=1, Q=4 and Q=10 follow the specified inclusive boundaries. Labels do not establish mechanical stability, a factor of safety or adequate support. The secondary assessment-information screen explains this project-defined simplification. Published NGI April 2025 tables, formula, official class boundaries, provenance and stored historical snapshots are unchanged. Full rating details still show the official NGI class. RMR89 is unchanged. No new geological calculation or empirical coefficient is introduced.

## Plan selection and revision compatibility

Mapping creates an immutable `MappingPlanSelectionRequest` from the same active plan used by the Plan tab, opening its loader directly in coordinate-selection mode. Confirming changes XY and source provenance only, with draft/context ownership rechecked. Context/draft changes dismiss stale destinations. If no active DXF exists, the shared tab selection opens Plan's existing «Загрузить DXF» empty state. Tab switching/import does not discard the unfinished Mapping draft.

Plans remain immutable revisions. Schema 8 gains only an optional `MappingPlanReference.frameConfirmation` containing a previous-plan UUID and explicit confirmation time, captured by «Система координат совпадает с предыдущей ревизией» during import. Missing fields mean no declaration; no upgrade chain or reinterpretation occurs. Pending import manifests retain the declaration through recovery. Old plans are never modified to add one.

Cross-revision overlays require the same horizon UUID (and therefore project), matching known units, and either fully qualified matching CRS/local-frame and axis metadata, or a connected explicit same-frame declaration. Generic `unknown` / `local` labels alone are not qualified frames. Declarations can connect unknown frame labels when the engineer explicitly confirms the common frame, but cannot override contradictory known CRS/axis identifiers or unknown/different units. Connected groups are checked for indirect contradictions. Missing references and cycles fail graph validation. No north, axis, unit or coordinate transformation occurs. Manually entered points without a source-plan reference remain excluded.

The overlay is bidirectional and spans all excavations by default. An observation keeps its original plan UUID, coordinates and provenance. Unknown/incompatible revisions show only their own points. Plan properties explain how to resolve missing overlays: import a new revision with a confirmed common frame or qualified metadata. A revision with unknown units cannot be used as a confirmation predecessor; reimport with confirmed source units/frame rather than editing historical evidence.

Plan has a compact native revision picker, secondary excavation filtering, an import/management toolbar action and 16 points of bottom control separation. DXF help and contextual properties remain available. Wedges retains required inputs, LiDAR, validation and results; repeated explanatory text moves to collapsed model assumptions. W1 and Phase 1 algorithms are unchanged.

## Verification and remaining device acceptance

Final focused SwiftPM run: **32 tests, zero failures** (10 third-review tests, 13 independent-measurement migration tests, and 9 selected mapping/NGI/lifecycle/attachment safeguards). The focused Xcode UI case passed on iPhone 17 Pro / iOS 26.5 Simulator: **1 test, zero failures**. It exercised nested measurement HOLD/cancel, manual J1–J5 acceptance, complete observation Save and canonical journal display after process relaunch. An initial test attempt failed before opening the editor while the presenter was attached to the lazy section; the final implementation hosts the modal at Mapping root and the successful retry uses viewport-checked taps. That initial failure is not attributed to a physical-device crash. Final iOS Simulator app build: **BUILD SUCCEEDED**, Xcode 26.6, generic iOS Simulator (arm64/x86_64), signing disabled for the command; only the App Intents metadata-extraction warning. Deterministic project generation twice produced identical project/scheme hashes; `git diff --check` passed. No complete XCTest or UI regression suite is requested or run. Core checks cover J1–J5 acceptance/save/reopen with precise sensor fixtures; copied-draft failures, cancel/retake isolation and stale owners; explicit independent-evidence recovery; decimal and historical pickets; Q boundaries; active-plan/no-plan navigation; bidirectional overlays across excavations and incompatible/dangling/cyclic frames. Existing selected checks cover measurement migration, sensor lifecycle, NGI arithmetic/classes, corrupt mapping refusal, external changes and missing attachments.

The targeted UI case opens the actual nested measurement screen, HOLDs/cancels DEMO capture, then accepts J1–J5 manually and saves/relaunches. Simulator DEMO north deliberately cannot be assigned as a geological representative; synthetic magnetic sensor conversion/save is checked separately by core tests. This distinction is not physical measurement validation.

On the owner's iPhone, still verify actual sensor acceptance for J1–J5, cancellation/retake, background/foreground, reopening original readings, active-DXF taps/import return, and Plan/Wedges spacing under normal keyboard/text-size conditions. Physical-device termination is not claimed resolved: no crash/Jetsam trace or real-device reproduction was supplied. If it recurs, capture the `.ips`/Jetsam report, device/OS/build, permission state and exact steps. Measurement accuracy remains physically unqualified.
