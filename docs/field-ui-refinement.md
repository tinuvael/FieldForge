# Field UI refinement — October 2026

Implements the field workflows requested in #38 and #48–53 against `main` at `9a4555a`. This document supersedes older descriptions of primary capture layout and Plan file-list navigation. UI remains Russian; native SwiftUI controls, light/dark semantic colors and existing deployment/signing settings are retained.

## Interactions and changed screens

- **Wedges / heading / dimension display:** all axis/B/H/L inputs share explicit focus management, a keyboard «Готово» action, interactive scroll dismissal and focus clearing before heading/LiDAR presentation and on departure. Dismissal never clears inputs. Sensor-populated fields show compact values while unfocused and restore full precision for editing; user-entered text is preserved.
- **Mapping main capture:** fixed project/horizon context remains. Current excavation is prominent; tap it for a searchable list, or tap «Создать выработку». Creation never silently selects or reassigns context. Existing discard confirmation still guards a context change. Main order is picket/date, XYZ/plan selection, J1–J5, advanced entry, ratings, notes, photos, Save. The toolbar ruler opens the existing approximate transient AR/LiDAR utility; its last result is in the services menu and never enters storage.
- **Joint-set sheet:** «Добавить систему» proposes the first unused J1–J5 identifier. Enter azimuth/dip manually, retain/select north, then explicitly accept the system. Direct manual compass acceptance creates a separate original entry retaining input text. Manual edits of a sensor-derived representative preserve the original sensor snapshot and show an explicit manual-modification badge; they do not manufacture a compass reading. «Замерить iPhone → Зафиксировать → Принять как Jn» stages an unchanged original and an explicitly accepted representative with its UUID evidence link. «Принять Jn» applies them to the live point draft; only point Save persists them. Retakes/replacements retain accepted originals as evidence. Removing an unsaved representative leaves its original readings available under advanced capture. Sheet cancellation asks before discarding changes and does not save. No averaging or north conversion occurs.
- **Mapping advanced / saved corrections:** interval bounds/position, tectonic descriptions and extra point originals remain accessible. Optional joint characteristics, authors and evidence links are under the joint sheet's «Дополнительно». Saved corrections retain the existing complete geology editor and cannot add/remove/rewrite original readings. Historical records are not reinterpreted.
- **Barton Q:** RQD plus five coefficient rows display selected values. Category selection uses existing NGI April 2025 rows and `QCoefficientInput.select`. Fixed values resolve as before; ranges remain empty until explicitly entered with the required rationale. Location/Jn and Jr/Ja contact appear contextually. Adjustments remain available with their dependent fields. Sources, optional descriptions and authors move to «Дополнительные параметры»; methodology and formula details move to «Методика». Incomplete/error status stays visible. RMR89 stays collapsed and input-only.
- **Draft photographs:** camera, Photos, Files, thumbnails, preview, retry and recovery warnings remain; explanations are secondary. Existing photo session/save guards and atomic relationships are unchanged.
- **Plan root / plan manager / horizon editor:** Plan directly loads the selected horizon's display revision with pan/zoom and source-qualified markers. «Планы и версии» manages files; the same manager is available after creating or editing a horizon through «DXF: план и версии». A new horizon stays open after saving so a DXF can be assigned before closing. «Показывать версию …» explicitly chooses a revision. Every original remains managed and hash-checked. No-plan state offers «Загрузить DXF». Point XY picking still lets the engineer choose any revision and identifies the draft's source revision.
- **Journal / point detail / marker selection:** excavation name is primary, picket secondary, date/horizon/revision supporting. Standard ordering is `observedAt` descending, then UUID string ascending. Effective-record queries, inclusive date filters, search, exports and immutable history remain unchanged. The standalone measurement journal/tools move to «Настройки → Обслуживание данных → Дополнительно».

## Display and data boundaries

`EngineeringDisplay` formats Russian decimal output without grouping or trailing zeros: angles up to one decimal, sensor-populated excavation dimensions up to two, distances/coordinates up to three, and Q/coefficient summaries up to four significant figures. Very small nonzero quantities retain significant figures rather than becoming false zeros; extreme magnitudes may use scientific notation. Example presentation: `135°`, `45,5°`, `4,25`, `393,125`, `0,1` for a binary artifact such as `0.10000000000000002`. Original typed text is shown during editing. Full coordinate precision is available in point detail; sensor diagnostic/source views retain raw values.

No formatter is used for calculations, stored values, CSV/XLSX or backups. Core Motion, Phase 1/W1 geometry, Q equations/tables/evaluator, schema 8, append-only journals, photo storage/export and source-plan relationships are unchanged. Bundle ID, signing, deployment and device installation configuration are unchanged.

Active-plan UI preferences live in `UserDefaults` under `FieldForge.activePlans.v1`, keyed by project/horizon UUID; values are validated against that project's horizon plans before use. Without explicit selection the last journal import is labelled as the default. Explicit selection persists across launches and is not replaced when another revision is imported. It is a disposable viewing preference, not an engineering revision or backup record. Deleting preferences falls back to the labelled import-order default. An invalid remembered choice falls back to the last available journal import, with a visible warning and revision-selection action; it is not counted as a valid explicit selection. No preference or journal entry is rewritten by the fallback. Changing context rebuilds the drawing; cancelled loads cannot publish into a new context. Selecting a display revision never changes saved or draft source-plan coordinates. No revision compatibility or coordinate transformation is inferred.

## Limitations and deferred qualification

- The existing Q evaluator requires RQD source and assessment source. These remain required under additional parameters, with mandatory-input counts and a direct expand action from the result summary. No defaults were introduced.
- Representative input supports the existing north enum contract. A sensor original with unavailable/DEMO north cannot be accepted directly as a representative; the measurement sheet offers «Оставить только исходный замер» for a savable held reading. The joint editor can then add only these originals to the parent draft without adding/changing a J system. A near-horizontal/vertical sensor result with missing direction that cannot satisfy the existing manual representative validator also remains original-only. No direction is invented. Manual exact horizontal/vertical inputs retain the existing explicit conventions and validation.
- New system sheets have local drafts until acceptance. Cancelling discards only that staged edit after confirmation; live point drafts remain memory-only until Save. No recovery-after-termination redesign was attempted.
- Existing full saved-correction editors are retained. Native iPad split layouts, independent physical sensor accuracy, surveyed transforms, persistent distance observations (#39), complete backup/restore and mechanical wedge analysis remain separate work.
- Existing UI test workflows expect the previous excavation Picker, separate measurement/system sections and services navigation. They need targeted updates before the next regression run; historical assertions and tests were not deleted or weakened in this package.

## Lightweight verification

Requested scope: no regression suite, simulator UI run, stress/performance run, physical-device installation or physical sensor validation. No tests or expected results were changed to hide behavior changes.

Performed:

- Fetched `origin/main` and confirmed the clean starting checkout matched `9a4555a`; reviewed #38 and #48–53 through the GitHub connector.
- Swift parser check of the changed capture, ratings, plan and formatting/model files.
- Deterministic `python3 scripts/generate_project.py`; project and shared scheme SHA-256 values were identical across two consecutive final runs (63 app sources, 24 unit test files, 3 UI test files).
- `git diff --check` and source/reference/diff review. No changes to Data, Core, Services/Export, Config, Resources, Tests, UITests or the project generator; project build-setting diff contains only source inventory additions.
- Exactly one Xcode 26.6 iOS Simulator app build, **BUILD SUCCEEDED**, for arm64 and x86_64:

  ```sh
  xcodebuild -project FieldForge.xcodeproj -scheme FieldForge \
    -configuration Debug -sdk iphonesimulator \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath /private/tmp/FieldForge-FieldUI-build \
    CODE_SIGNING_ALLOWED=NO build
  ```

  Signing was disabled only for this command; checked-in signing settings were not changed. The only reported build warning was skipped App Intents metadata extraction because there is no AppIntents dependency. Build outputs and log remain outside the repository in `/private/tmp`.

Deliberately skipped per owner instruction: `swift test`, XCTest/regression suites, simulator UI tests and app launches, stress/performance checks, device installation and physical sensor/AR accuracy validation. No regression or physical acceptance success is claimed. This delivery includes implementation for #48–53; on-device UX acceptance and the targeted UI-test updates remain outstanding, so issue references should not imply completed physical qualification.

## PR #54 final review corrections

The follow-up review started from clean PR head `99829b8` and confirmed all three reported issues in the current source. Corrections are limited to existing UI/model files; no source inventory, persistence schema, formulas, tables, source measurements, history, photo/DXF originals or export settings change.

### Actionable Q capture

The capture summary consumes the **actual** `BartonQInput.evaluate()` result. Missing numerical inputs (RQD/Jn/Jr/Ja/Jw/SRF), range rationales, classification conditions, required sources and adjustment information are grouped into short actions directly under the result. Numerical/range actions open the same bound coefficient controls; other actions expand the corresponding adjacent disclosure. Disclosure labels count outstanding mandatory requirements, including «Дополнительные параметры». Invalid input/selection/condition errors remain distinct from missing data, showing the evaluator's actual error and repair actions. The evaluator short-circuits on the first invalid value/condition; the complete missing list becomes available after that error is corrected. UI message routing does not decide validity or fabricate missing inputs.

Inspected evaluation requirements:

- Finite RQD in 0…100; original value retained.
- A valid published row for every coefficient and a positive explicit value within its row. Fixed-row choices still resolve through `QCoefficientInput.select`; range choices still clear the numerical value and require explicit input and rationale.
- Explicit RQD source, Jn location and Jr/Ja wall-contact condition; assessment source must not be blank.
- Jr/Ja category/contact compatibility and the existing Jr +1 restrictions; spacing >3 m when that adjustment is chosen.
- SRF adjacent-zone rows A–E versus shallow-crown row F restrictions; an explicit 25…50% reduction only with the adjacent-zone adjustment.
- A rationale for each ranged coefficient and for any adjustment; no automatic coefficients or geological inference.
- Existing residual spacing/reduction fields remain reachable for correction rather than being hidden when their selector changes.

Whether source/provenance should gate the displayed classification or only final assessment acceptance is a separate methodology/product decision. This package preserves the current contract; it does not assert that NGI itself requires the application's free-text source field. Any change requires a separately reviewed evaluator/provenance policy.

### Active DXF selection — logical scenario review

| Scenario | Code path after correction |
| --- | --- |
| A: one plan, no preference | Last available import opens automatically. |
| B: two plans, revision 1 explicitly selected | The validated selected ID wins over import order, including subsequent visits. |
| C: invalid selected ID, another plan exists | Last available import opens; warning and «Выбрать ревизию» are shown. `hasExplicitPlan` is false; the manager allows confirming the fallback or choosing another revision. |
| D: project/horizon switch | Available plans are qualified by selected project and horizon. Existing view identities and cancelled-load checks prevent publishing the previous drawing; the manager refreshes pending imports for the new horizon. |
| E: import a revision | Registration remains append-only. Valid explicit selection remains in effect; fallback/default uses import order. Original plan IDs and historical coordinates are not changed. |

A reference whose original is missing/corrupt on disk still shows the existing loader integrity error. The fallback handles an unavailable **selection ID**, not replacement of damaged originals. Stale preferences remain intact until explicit revision selection; no automatic journal or preference repair is performed.

### J1–J5 evidence and cancellation review

- Manual compass input uses the existing validator and preserves entered text in a separate original. A sensor representative is created only through explicit acceptance and the same existing representative validator.
- Savable held readings with unsupported north or ambiguous/incomplete representative orientation can be explicitly retained as originals. The editor provides an original-only action even while the J fields are invalid. Invalid/uncertain sensor readings still cannot be saved; quality gates are unchanged.
- Staging rejects duplicate original UUIDs before mutating local state. Applying to the parent first validates a copied draft, new originals, the representative/evidence links, five-system limit and unique identifiers/UUIDs. Only then is the parent draft published once. A stale parent draft or active save blocks application.
- Cancel/retake do not change the accepted representative. Cancelling the joint editor with local changes requires explicit discard and leaves the parent unchanged. Retained readings are not persisted until the normal point Save.
- Editing a sensor-derived representative manually preserves all originals and evidence links, shows «Представительная ориентация изменена вручную», and avoids fabricating a new compass measurement. The badge can also be derived when reopening a draft with linked sensor evidence; the persisted interpretation remains the existing `user-interpretation-v1` record.
- Removing a draft J system removes only that interpretation; point originals and evidence used by other systems remain. New identifiers come from the first unused J1–J5 slot, with uniqueness checked again before publication.
- The joint editor retains keyboard «Готово» and scroll dismissal. Held sensor notes now also have focus management and keyboard «Готово»; opening/accepting/retaking clears focus without changing entered data.

These are source/state-flow inspections, not executed runtime or device acceptance tests. The owner's next iPhone walkthrough remains required, including original-only retention, Q repair navigation, stale DXF preferences and keyboard transitions J1 → J2.

### Follow-up lightweight verification

Performed in this review pass:

- Reviewed current PR head/branch `99829b8`, the complete Q evaluator and the six changed Swift files; inspected state, bindings, acceptance/cancellation and DXF scenarios A–E logically.
- Swift parser check of `MappingRatingsForm`, `MappingModel`, `ActiveHorizonPlanView`, `HorizonPlansView`, `MappingJointSetsSection` and `MappingMeasurementSheet`.
- `git diff --check` (working changes and full review diff).
- Ran `python3 scripts/generate_project.py`; project and scheme hashes remained identical to the pre-review files. No source inventory or generated project changes.
- Exactly one final Xcode 26.6 app-target build for this review pass: **BUILD SUCCEEDED**, arm64 and x86_64 iOS Simulator:

  ```sh
  xcodebuild -project FieldForge.xcodeproj -scheme FieldForge \
    -configuration Debug -sdk iphonesimulator \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath /private/tmp/FieldForge-PR54-review-build \
    CODE_SIGNING_ALLOWED=NO build
  ```

  Only reported warning: App Intents metadata extraction skipped because no AppIntents dependency is present. This command does not change checked-in signing settings. Artifacts/log are outside the repository in `/private/tmp`.
- Confirmed no review diff in Data (including `RockMassRatings.swift`), Core, Services/Export, Resources, Config, Tests, UITests, generator or Xcode project.

**Regression tests were not run.** Deliberately skipped: `swift test`, XCTest/regression suites, simulator UI tests/app launches, physical-device installation/tests, performance/stress campaigns and physical sensor/AR validation. No runtime/device acceptance or measurement-accuracy success is claimed. The earlier implementation-pass build above is historical; this review pass used one additional final build.
