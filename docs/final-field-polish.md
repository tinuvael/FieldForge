# Final field polish and field Excel export

2026-10-21, follow-up on open PR #56. This document supersedes historical input-only RMR and default-CSV presentation descriptions. It does not expand the three-module product scope.

## Coordinates, Wedges and plan properties

Mapping and correction forms show «Координаты», X, Y, Z and «Выбрать на плане». Unfocused coordinates have exactly one decimal; focusing restores the entire original text. A small UIKit boundary adapter replaces formatted display in `textFieldDidBeginEditing`, before the first key, so iOS cannot retain the formatted value as editable input. Only explicit `editingChanged` events write to the input binding. Saving still uses original precision and the existing XY units, CRS, axes, source plan, Z origin and source-horizon elevation. Unknown drawing units and millimetres are never treated as metres or scaled.

Automatic Z snapping to nearby walls is **future work**, requiring qualified georeferenced elevation/3D geometry. Nominal horizon Z remains a recorded default, not a surveyed wall elevation. Detailed units and source information remain in observation details and collapsed correction metadata.

Wedges uses consistent Form rows for axis, axis capture, north, B/LiDAR, H/LiDAR and L. A valid unfocused axis shows `285°`; editing shows `285`. Existing 0–360 validation, north compatibility, geometry and sensor captures are unchanged. The keyboard dismissal bar reserves its own full-width safe-area space above the numeric keyboard. It does not cover the form. Original LiDAR readings, calculated arch/wall heights and geometric assumptions remain in collapsed details; live magnetic-field magnitude moves behind technical disclosure. North labels and incompatible-reference warnings remain visible.

The plan canvas, original-file verification, active revision selection and overlay qualification are unchanged. «Сведения о плане» contains filename/revision/horizon/import time/units, per-revision compatibility and an actionable import warning. «Технические сведения» starts collapsed and retains source UUIDs, complete CRS/axes, unit declarations, import confirmation, parser warnings and selectable monospaced SHA-256.

## Preliminary basic RMR89

Published method: Bieniawski, Z.T. (1989), *Engineering Rock Mass Classifications*, Wiley, ISBN 0-471-60172-1, Table 4.1 A/C/E. Tables and special-condition footnote were checked against E. Hoek, *Practical Rock Engineering*, [Rock mass classification, Table 4, printed pp. 9–10](https://www.rocscience.com/assets/resources/learning/hoek/Practical-Rock-Engineering-Chapter-3-Rock-Mass-Classification.pdf), accessed 2026-10-21. Its worked example independently supplies the acceptance calculation below. This is a preliminary classification tool, not support design or mechanical wedge assessment.

The operator explicitly chooses the test basis and published categories. No descriptive text, source or author is required to preview the basic number. Measured values and original evidence remain optional secondary fields; any supplied numeric value must agree with the selected category. Source descriptions are never interpreted as categories automatically. New classifications do not group original orientations or reuse Q coefficients.

| Component | Categories in displayed order | Ratings |
| --- | --- | --- |
| UCS, MPa | >250; 100–250; 50–100; 25–50; 5–25; 1–5; <1 | 15, 12, 7, 4, 2, 1, 0 |
| Is(50), MPa | >10; 4–10; 2–4; 1–2 | 15, 12, 7, 4 |
| RQD, % | 90–100; 75–90; 50–75; 25–50; <25 | 20, 17, 13, 8, 3 |
| Spacing, m | >2; 0.6–2; 0.2–0.6; 0.06–0.2; <0.06 | 20, 15, 10, 8, 5 |
| Persistence, m | <1; 1–3; 3–10; 10–20; >20 | 6, 4, 2, 1, 0 |
| Aperture, mm | None; <0.1; 0.1–1; 1–5; >5 | 6, 5, 4, 1, 0 |
| Roughness | Very rough; rough; slightly rough; smooth; slickensided | 6, 5, 3, 1, 0 |
| Infill | None; hard <5 mm; hard >5 mm; soft <5 mm; soft >5 mm | 6, 4, 2, 2, 0 |
| Weathering | Unweathered; slightly; moderately; highly; decomposed | 6, 5, 3, 1, 0 |
| Water, descriptive basis | Dry; damp; wet; dripping; flowing | 15, 10, 7, 4, 0 |

Published ranges have shared endpoints. This version does **not** invent an automatic tie rule or interpolate ratings: the engineer explicitly selects the applicable published band, which is saved verbatim by stable category ID. A measured shared endpoint may agree with either adjoining published band. Open endpoints remain strict (e.g. >250, <0.1). Is(50) below 1 MPa has no supported rating; UCS is required. There is no Is(50)-to-UCS conversion. Groundwater uses explicit descriptive categories; stored inflow/pressure data are preserved as evidence, not silently substituted for that basis.

For unfilled joints, the Table E five-part condition sum is used. The source footnote requires A.4 when gouge masks roughness. With infill, the operator must explicitly select the full A.4 description, including continuity. The E sum is not used. Thin filling requires the matching 10-point A.4 category; soft filling >5 mm or aperture >5 mm requires the matching 0-point category. Conflicting A.4 selections fail validation. The source does not uniquely specify hard filling >5 mm in A.4; **that case remains incomplete**, pending qualified engineering clarification, rather than receiving an invented overall rating. Exactly 5 mm is not silently assigned to either open infill range; the form directs the assessor to review A.4. Geological suitability/continuity remains an explicit engineering interpretation.

Basic RMR is strength + RQD + spacing + condition + water. Class boundaries are I 81–100, II 61–80, III 41–60, IV 21–40, V 0–20. The UI explicitly labels the class as belonging to **basic** RMR. No orientation correction is assumed, even if application/orientation descriptions exist. Tunnel/mine, foundation and slope corrections remain unavailable and are never interchanged.

Independent published example: Is(50)=8 MPa, RQD=70%, spacing=0.3 m, persistence=1–3 m, aperture=0.1–1 mm, slightly rough, no infill, slightly weathered, wet. `12 + 13 + 10 + (4+4+3+6+5) + 7 = 64`, class II. The source's adjusted 59 includes a separate −5 tunnel correction; FieldForge does not apply it.

### Persistence

Schema remains **8**, with no migration, reset or evidence rewriting. Optional `basicSelections` on the existing input and optional `calculation` on the assessment distinguish new `Bieniawski-RMR89/basic-categories-v1` snapshots from `Bieniawski-RMR89/input-only-v1`. Legacy missing lists/inputs validate with the original rules and remain uncalculated. New snapshots store component ratings, missing inputs and optional total; load/save checks reproduce them using the exact method and original selections. A missing calculation payload on the new method, an unknown method or a corrupted result fails closed. Incomplete selections remain valid explicitly incomplete assessments. Corrections append a new observation revision; they preserve prior assessments, descriptions, original readings and evidence UUID relationships.

## One-file Excel workflow

Normal export is «Экспортировать Excel» with project, optional horizon/excavation filters, inclusive field-date range and observation count. Timezone administration, CSV, technical-sheet visibility and long format notes are secondary. The selected Gregorian calendar/timezone still defines the same half-open UTC period, including the whole final calendar day. Changing timezone retains calendar labels. The export view freezes the saved journal independently of the active unsaved draft.

`FieldForge-Mapping-XLSX/2` produces exactly one `.xlsx` URL for `UIActivityViewController`. First visible sheets:

1. «Наблюдения»: one effective observation, project/horizon/excavation/picket, field date, numeric XYZ, declared XY units, J1–J5 azimuth/dip/north, Q/FieldForge category, calculated basic RMR/class and notes.
2. «Системы трещин»: one accepted interpretation, parent observation reference, identifier, numeric orientation, north and geological properties.
3. «Тектоника»: parent observation, structure identifier/type, available numeric orientation, north, thickness and description.
4. «Рейтинги массива»: stored numerical Q/basic RMR, classifications, principal measured inputs, RMR component ratings, selected categories and missing values. Orientation-adjusted RMR is explicitly unavailable.
5. «Фотографии»: parent observation/photo references, original filenames, metadata, capture/import dates and capture-location provenance. Each row explicitly states that image bytes are excluded.

«Сводка» follows. The complete existing 14 technical tables follow with unchanged original readings, evidence joins, exact input text/JSON, units/provenance and photo historical context. Three optional RMR calculation columns extend `assessments` without moving any existing columns or changing old rows' meaning. `field_links` maps workbook-local references (e.g. Н-1, Н-1/J1, Н-1/Т-1, Ф-1) to full original/revision UUIDs. These references are local to the frozen workbook, not new persistent identities. Technical sheets start hidden and can be shown using the export toggle or the spreadsheet application's unhide command. Photo ZIP keeps its full register/manifest and verified original-image paths.

Field coordinates/angles/ratings are real numeric cells. Coordinates/angles display one decimal; stored values are not rounded. Field dates are Excel numeric civil timestamps in the selected timezone, with date/time formatting. Technical UTC strings and exact epoch seconds retain the original instant/precision. Excel's approximately 15 significant-digit limit applies to field numeric analysis. Higher-precision raw values remain exact text on technical sheets. Pickets are text with plus signs and decimal commas. Blank/unknown values stay blank. Headers are frozen and filtered, columns have readable widths, long text wraps with bounded row heights. All user strings are inline text; no formulas/macros/external links are emitted.

CSV remains UTF-8 **with BOM**, comma-separated, quoted, CRLF, decimal-point numbers and protected formula-like strings. Russian Excel installations may expect semicolons or a different encoding on direct opening: use **Data → From Text/CSV**, select UTF-8 and comma delimiter. Such an import/display mismatch does not establish XLSX corruption. Ordinary XLSX uses UTF-8 OOXML inside ZIP and needs no CSV encoding/delimiter selection. The owner's original problematic files were not supplied, so their exact failure cause is not claimed.

This is an analysis export, **not a complete backup**: ordinary XLSX excludes original images/DXF and full correction audit history. Photo ZIP remains an explicitly separate operation with missing-original reports and existing incomplete-package confirmation.

## Verification

The representative fixture is produced by the actual Swift application exporter in isolated temporary directories. It has three observations/dates, Cyrillic project/excavation/geology, symbols °/μ/µ/≤, decimal-comma pickets, high-precision coordinates, blank values, stored Q and calculated/legacy RMR, J1–J5, tectonics and an unknown-location photograph. A second workbook exercises visible technical sheets. No personal journals/images are used.

`scripts/validate_mapping_xlsx.py` independently reads ZIP CRCs, all XML/relationships/content types, worksheet order/state, numeric/date/text types, headers/filters/styles, exact raw precision, literal formula-like strings, nulls and UUID joins using Python **openpyxl 3.1.5**. It verifies 28 package parts, 21 sheets and 885 typed cells in the representative workbook. A separate retained P5.2 fixture verifies 313 typed technical cells. This is actual workbook reading, not only ZIP construction. Desktop Microsoft Excel, Apple Numbers, LibreOffice and WPS have **not** been opened for acceptance; no application-specific compatibility claim is made.

Focused SwiftPM checks cover reference arithmetic, every rating row, classification boundaries, measured/category agreement, incomplete/contradictory choices, low Is(50), infill exceptions, legacy JSON, corrupted result rejection, current-journal round-trip, append-only corrections and original evidence, single default XLSX, cancellation/failure cleanup, CSV, photo packages, existing NGI/Q and W1 checks, experimental current-schema refusal and the independent measurement migrations. Simulator UI/build results are recorded in the PR. Physical iPhone accuracy, field acceptance and automatic Z snapping are not claimed. The next product step is real field-data testing.

### Recorded results

- SwiftPM: **92 selected tests passed, zero failures, zero skips**. Both independent workbook fixtures were generated during this run (`/tmp/fieldforge-final-tests.log`). The independent original-measurement migration suite remains included.
- Xcode iOS unit tests: **10 passed, one opt-in fixture skipped**, zero failures, iPhone 17 Pro / iOS 26.5, Xcode 26.6. The skipped generator is exercised in the macOS SwiftPM run instead; actual workbook reading is reported above.
- Quick RMR UI: passed without entering source/descriptive text, producing basic 64 and class II. Result bundle: `/tmp/FieldForge-FinalPolish-Final.xcresult` (the earlier combined UI run also contains a share-title test query failure; the system exposed the correct XLSX caption as an accessibility Other element rather than StaticText).
- Coordinate/one-XLSX-share and Wedges UI: **2 passed, zero failures**, iPhone 17 Pro / iOS 26.5 (402 × 874 pt). Final result bundle: `/tmp/FieldForge-FinalPolish-Acceptance.xcresult`. This checks exact raw text on re-entry, unfocused one-decimal coordinates, `285° ↔ 285`, native numeric keyboard dismissal and the actual `FieldForge-Mapping.xlsx` caption in the system Share Sheet. Together with the separate RMR result, three distinct targeted UI scenarios passed.
- Project generation: identical project/scheme SHA-256 before/after two consecutive runs (67 app sources, 26 unit-test files). `git diff --check` passed.
- Final standalone iOS Simulator build: **BUILD SUCCEEDED**, Xcode 26.6, signing disabled (`/tmp/fieldforge-final-build.log`). Successful UI screenshots were inspected for coordinate labels, equal geometry rows, degree display, the reserved keyboard bar and one XLSX share caption.
- Plan properties: source/layout review and app compilation; no separate plan-properties interaction acceptance test was run.

The initial targeted UI checks exposed formatted text surviving re-focus in SwiftUI fields. `LosslessNumericField` replaces it through native editing callbacks and tracks native focus as ordinary view state. UI tests check the exact unrounded coordinate input on re-entry, degree removal/reappearance, actual numeric keyboard dismissal and the button's position above numeric keys. No physical iPhone acceptance or accuracy is claimed.
