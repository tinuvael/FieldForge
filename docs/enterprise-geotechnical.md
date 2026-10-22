# Enterprise geotechnical mapping

This functional extension starts at `main` commit `229d1b3` (merged PR #56). It adds no structural/scanline mapping, wall-orientation capture, weighting, north conversion, mechanical wedge calculation or runtime dependency. UI text is Russian. The existing three primary modules, measurement algorithms, DXF/coordinate contracts, original-measurement journal and NGI April 2025 Q tables/evaluator remain unchanged.

## Verified sources and scope

- Owner-supplied enterprise methodology, Appendix 6, Section 2, Tables 3, 4 and 6. The supplied DOCX has SHA-256 `c759076c8f7f22c9ba112ad71ce0c01650abf72760841baf881c8fe94b361ee9`. Only compact category definitions/ratings needed for the feature are implemented; the private document and figures are not bundled.
- Priest, S.D. & Hudson, J.A. (1976), *Discontinuity Spacings in Rock*, IJRMMS 13(5), 135–148, [DOI 10.1016/0148-9062(76)90818-4](https://doi.org/10.1016/0148-9062(76)90818-4), equation 5. Also Brady & Brown (2004), *Rock Mechanics for Underground Mining*, equations 3.3–3.4, as specified by the owner.
- Bieniawski (1989), *Engineering Rock Mass Classifications*, existing RMR89 A/C/E category evaluator. Field grades R0–R6 are approximate ISRM strength intervals reproduced in enterprise Table 6; ratings are 0, 1, 2, 4, 7, 12, 15.
- Bieniawski (1976), joint condition, independently verified in [Hoek, Carter & Diederichs (2013), Appendix 1, Table 2](https://www.rocscience.com/assets/resources/learning/hoek/Quantification-of-the-GSI-Chart-2013.pdf). JCond76 values are 25, 20, 12, 6, 0. No quantitative GSI correlation from that paper is applied.
- Read & Stacey (2009), *Guidelines for Open Pit Slope Design*, §5.4.4, Table 5.34, Hoek–Brown 2000 / Marinos & Hoek (2000), inspected in the owner's connected Drive copy. Table 5.34 appears on printed page **126**, PDF page 141, in that copy (the request cites printed page 127). The table identity, categories and N/A cells were verified visually and against extracted text. No chart image, geological sketch, copied contour geometry or private PDF is included in the repository.

## SD contract

`InterpretedJointSet.spacingMeters` remains the single effective spacing in metres. Its optional `spacingProvenance` contains source, method version, original RQD, RQD input owner and source evidence. Missing provenance means `unknownLegacy`; old spacing is preserved, including old zero values. New draft sets start in automatic mode, even when no estimate is available. A direct spacing edit marks only that draft set `manual`; clearing is an explicit manual absence. New manual input must be finite and strictly positive: zero (including signed zero), negative and non-finite entries cannot be accepted or saved. Untouched legacy zero evidence remains unchanged and excluded from the mean. «Оценить по RQD» explicitly restores automatic mode. Presentation uses two decimals with lossless full-value editing; storage and exports do not round the engineering value.

`Priest-Hudson-1976/negative-exponential-bisection-v1` solves

```
RQD = 100 exp(-0.1 λ) (1 + 0.1 λ)
SD = 1 / λ
```

in the dimensionless variable `x=0.1 λ`, using a growing bounded bracket and 160 bisections on `log(1+x)-x`. A small-x series avoids cancellation near 100%; logarithmic evaluation handles very small positive RQD. Only finite `0<RQD<100` produces finite positive spacing. Endpoint, absent and invalid inputs produce no estimate. RQD=70% gives approximately **0.09112869360510292 m**, presented as **0.09 m**. The assumption is a negative-exponential distribution along a sampling line: observation RQD does **not** uniquely establish spacing of an individual joint set. These values are estimates, never labelled measured evidence.

The original Barton Q input RQD is preferred, without Q's numerical minimum replacement of 10%. If absent, RMR89 original RQD is an explicit, visibly labelled fallback. If both supplied RQD inputs disagree or either is invalid, a visible discrepancy blocks automatic estimates until the inputs are reconciled. Ratings retain their independent inputs and are not modified to support SD.

RQD/source changes update only automatic values in the active `MappingDraft`, including correction drafts. Acceptance of a staged system refreshes automatic provenance from the owning draft. Legacy/manual values do not change. Rehydration restores saved sets **after** loading Q/RMR inputs, preserving exact historic snapshots. Saving a correction increments only changed local joint revisions through the existing correction path; saved historical revisions are never edited or refreshed on read/export.

`JointSpacingMean` includes positive finite effective spacing from saved accepted J1–J5 only. It uses an ordinary arithmetic mean with no orientation, persistence, RQD or system-count weighting. Missing/zero values are excluded; no valid values yields a missing mean and count 0. Export identifies **«SD среднее, м»**, count and whether the mean contains RQD estimates. 0.20, 0.40 and 0.09 produce 0.23; if the third value is the unrounded 70%-RQD estimate, the precise mean is approximately 0.230376231201701.

## ROCK and RMR89

Optional `MappingObservation.rock` freezes a separate exact numeric code string and optional name. Numeric identity is kept as text to preserve leading/trailing zeroes; there is no invented mine-specific dictionary. «Коды пород проекта» appends project-owned codes/names; duplicate exact codes and replacement/removal of saved dictionary entries are refused. Changing a project's name or adding codes does not alter observation snapshots. ROCK edits use the ordinary observation correction history.

RMR89 offers one active strength method: field R0–R6, UCS or Is(50). The field category carries its grade, published rating and `ISRM-R0-R6/enterprise-table6-v1` method; no exact UCS is fabricated. Switching methods clears the current draft's strength category; entering field mode also clears its exact laboratory value. Prior saved inputs remain in history, and the existing lab-to-lab input behaviour is retained. The evaluator uses a single strength component. Mixed field/laboratory scoring is rejected and Is(50) is not converted to UCS. New calculated field-strength assessments use `Bieniawski-RMR89/basic-categories-field-strength-v2`; existing input-only/basic-v1 assessments retain exact validation and results.

Optional `RMR89Input.jcond76` stores category, rating and `Bieniawski-1976/JCond76-Hoek2013-table2-v1`. Its timestamp belongs to the enclosing RMR assessment. It appears **inside RMR89** and never changes the RMR89 condition subtotal or basic sum. Category/rating/method consistency is revalidated on load/save. It is independent of the existing RMR89 A.4 and E condition categories.

Enterprise A1 is exported from the explicitly selected field grade only. A42/A43 map from verified explicit RMR89 persistence/aperture categories, retaining the engineer's choice at shared endpoints. A45 maps only the first four corresponding weathering categories. Enterprise A45=0 describes crushed walls, whereas RMR89's last category means decomposed: that mapping is intentionally absent. Free text, raw dimensions and Q categories are not guessed into enterprise categories.

## GSI interaction and verification boundary

The order is Barton Q → RMR89 (including JCond76) → GSI. GSI has an original SwiftUI **categorical** matrix with six readable structure labels, five surface categories and at least 44-point buttons. A tap selects the category cell centre; explicit confirmation commits it to the owning observation draft. The sheet stages changes locally. Returning without confirmation retains the existing assessment.

`Read-Stacey-2009/table5.34-HoekBrown2000/categorical-explicit-interval-v1` preserves structure, surface, normalised categorical centre `(x,y)`, an explicitly entered lower/upper GSI interval, optional refined final GSI and assessment timestamp. No number is inferred from a tap, Q, RMR89 or JCond76. Contours have **not** been numerically digitised. The categorical fallback is **not a replacement for the full Table 5.34 chart**; its limitation is displayed immediately on opening GSI, before the category controls. The engineer must choose an interval (0–100, lower ≤ upper). The optional final value must satisfy **lower ≤ finalValue ≤ upper**, inclusively; it does not erase the chart selection or interval. Out-of-range refinement disables confirmation and reports a visible validation error. Further edits of saved points create normal corrections.

Verified N/A combinations are massive × poor/very poor and laminated/sheared × very good/good. They are disabled in the UI and rejected in stored assessments. Altered method/position metadata is rejected. Details retain the warning that dominant oriented weakness, such as unfavourable persistent discontinuities, may invalidate GSI. The feature produces no direct stability or support recommendation.

## Separate enterprise workbook

«Геотехническое картирование — регламент» opts into an additional value-owned export snapshot through the same selection/date filters and native Share Sheet. Ordinary XLSX/CSV/photo exports use their original preparation contract (the field workbook strength-method cell also recognises R0–R6); enterprise history is prepared only when requested. The existing OOXML/ZIP writer emits one `.xlsx`, exactly three **visible** sheets, no hidden technical sheet, formula, macro, image original or external relationship:

1. **Геотех картирование** — one effective saved observation per row, even if incomplete. Context/date, declared coordinates/units/CRS/axes, frozen ROCK, original RQD/source/discrepancy, original and effective Q coefficients, stored Q/basic RMR/class, field grade/A1, independent JCond76, GSI interval/refinement, per-system SD/orientation/north, SD mean/count/estimate flag, verified A42/A43/A45, all tectonic structures (numbered numeric column groups), descriptions and exact observation/revision IDs and method versions.
2. **Справочники** — relevant category definitions, code/rating versions, GSI category and N/A rules, explicit numeric-verification limit, configured project ROCK dictionary (also for an empty selection), SD origin/method/assumptions, enterprise parameter mappings and source attributions. No proprietary source file/chart is bundled.
3. **Исходные данные** — scalar audit records for original selected observations, every existing correction snapshot/reason/predecessor, original measurements and diagnostics, photo records and metadata revisions/attachment hashes. Record UUID + field path is stable within the saved record. Observation/revision UUID/version and field context accompany each scalar. Paths preserve the encoded model keys and array indices, including child IDs, original input strings, north and numerical method metadata. Explicit SD `source` rows mark absent legacy provenance as `unknownLegacy`. A missing optional property stays absent, never a zero. Dates inside records retain reference-epoch seconds; every numeric scalar has full-precision text separately from its Excel cell. Long source strings split into numbered lossless chunks. No EXIF coordinates are read or inferred. Attachment availability is not checked.

First-sheet engineering values remain numeric; exact raw numbers are also preserved on the source sheet beyond Excel's 15-significant-digit limit. Date cells use the explicitly selected export time zone; original time zone/offset/instant remain in raw records. This report is an analysis/audit artifact, **not a complete backup**: original photos, DXF bytes and restore operations are outside it.

## Persistence

Mapping stays on experimental **schema 8**. Additions are optional Codable fields; absent fields decode to their historic meaning. No mapping schema migration, reset, old-format acceptance, old file deletion or original-measurement-journal change is introduced. Current-schema atomic saves, `.previous`, external-change guards, relationship checks and append-only originals/revisions remain in force. New assessment method/rating/value metadata is validated, and saved dictionary codes are append-only. Reopening an assessment does not recalculate history.

## Reproducible validation

```
swift test
FF_ENTERPRISE_FIXTURE_DIR=/tmp/enterprise swift test --filter EnterpriseGeotechnicalTests
python3 scripts/validate_enterprise_xlsx.py /tmp/enterprise
python3 scripts/generate_project.py
```

The Python check requires development-only openpyxl and independently opens ZIP/OOXML/Excel, verifies exactly three visible worksheets, one observation row, numeric mean/count, dates, Cyrillic, blank fields, provenance and full precision text. Fixtures are synthetic and temporary. `EnterpriseGeotechnicalTests` runs through both SPM and Xcode. See the PR for final build/UI results and baseline failures. No physical iPhone validation is claimed.

### Verification recorded 2026-10-21

- `swift test`: 296 tests executed, 1 optional fixture skipped, **2 existing failures**; both reproduced from unchanged `main` (`229d1b3`) in `/tmp` before attributing them to this extension. `DXFRealTests.testOriginalFileStoragePickingZDraftMarkersIsolationAndCorruptImportPreserveEvidence` attempts an already registered plan revision. `P33RevisionTests.testQRecalculationUsesFrozenMethodAndRMRRemainsInputOnly` expects the old Q version string although main already creates `FieldForge-field-2`. These tests/methods were not changed to hide the failures.
- All **16** new `EnterpriseGeotechnicalTests` pass in SwiftPM and Xcode Simulator. They cover numerical inversion/endpoints, all five initial systems, independent/manual overrides, RQD update/fallback/conflict, reset, legacy source preservation, saved means/counts, atomic restart/corrections, new-assessment corruption refusal, exact ROCK, field/laboratory strength and independent JCond76, GSI N/A/method/position validation, history and all workbook export modes.
- Xcode 26.6 / iPhone 17 Pro Simulator / iOS 26.5: simulator build passed. UI tests `testEnterpriseSDAndGSICategoricalWorkflow`, `testEnterpriseFieldStrengthAndJCondInsideRMR` and existing `testFinalPolishQuickRMRBasicWithoutRepeatedDescriptions` passed. SD native-field focus was corrected during this verification. The saved GSI screenshot was inspected: category labels, selectable point and four disabled N/A cells are legible without zoom.
- Independent `zipfile`/OOXML/openpyxl checks pass for both the enterprise workbook (exactly three visible sheets, one effective observation, 329 scalar audit rows in the synthetic revision fixture) and the existing ordinary workbook (21 worksheets, 885 typed cells). CSV/photo-package and original-measurement compatibility tests are included in the full SwiftPM run.
- Two consecutive `generate_project.py` runs produce identical project SHA-256 `ace47ba364f52b312b7075b839979de751214527821499d20458c319a6e3a92a`; `git diff --check` passes. No source artwork, private methodology document, personal journal, credential or generated build output is committed.
- Physical iPhone measurement accuracy, field reliability and real-device validation were **not** tested in this iteration. No engineering safety/support recommendation is produced by the new features.

### PR #57 validation follow-up — 2026-10-22

Manual SD validation now rejects SD ≤ 0 in the existing joint-draft validation path. Empty spacing remains optional; untouched legacy zeros retain their original stored value. No store, schema, observation-save/correction mechanism, Q/RMR89 method or export structure changes are made. Focused tests exercise acceptance, first save and correction refusal, preservation of current/previous files, positive/missing values and legacy behavior.

GSI refinement is restricted to the inclusive selected interval, including singleton intervals. Tests cover both endpoints, just-outside values, non-finite input, reload and unsuccessful/successful corrections without changing the original selection or history.

Table 5.34 was inspected again in the same source copy. The diagram provides qualitative category axes and drawn numerical contours, some without individual numeric labels, rather than a complete tabulation of coordinates and numerical boundaries. No independently verified contour dataset / boundary test oracle is available in this task. Assigning values to traced paths or interpolating screen coordinates would add assumptions that have not been independently engineering-validated. Consequently no numerical graphical-point method is claimed or implemented. The UI now explicitly identifies the categorical matrix as category selection rather than the full Read & Stacey diagram; manual range/refinement entry and verified N/A cells remain available. A future graphical implementation needs a reviewed contour dataset with independently checked region/boundary cases; it must not silently reinterpret existing categorical centres as continuous chart points.

Follow-up verification: all **20** `EnterpriseGeotechnicalTests` pass in SwiftPM and Xcode 26.6 / iPhone 17 Pro Simulator / iOS 26.5. The updated `testEnterpriseSDAndGSICategoricalWorkflow` passes with explicit UI checks that manual SD=0 and final GSI=46 outside [35,45] cannot be confirmed; valid values, reopening and export still work. Full `swift test`: 300 tests, 2 optional-fixture skips, the same 2 pre-existing DXF/Q failures documented above. Project generation remains deterministic with the same SHA-256; `git diff --check` passes. Q/RMR89 method files, exporter files, the schema and store/correction mechanism are unchanged by this follow-up. No physical-device validation is claimed.
