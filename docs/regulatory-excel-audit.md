# Regulatory Excel, RMR editions, joint sets and import audit

> Stage 3a implements the [routine J1–J4 workflow and field category selections](enterprise-geotechnical.md#regulatory-field-categories-stage-3a). The decision register below records the earlier audit state.

Status: Stage 1 specification, 2026-11-07. Audited application revision:
`a559ee9d575b4da63b67ac66b3713845450bed61` (merged B2b, PR #72).
The current [Stage 2 export contract](enterprise-geotechnical.md#regulatory-data-workbook)
documents the implemented regulatory workbook and its limits. The code inventory,
method comparison and later-stage gates below record the Stage 1 audit.

The owner's current instruction supersedes the old custom regulatory layout in
[#74](https://github.com/tinuvael/FieldForge/issues/74): the primary sheet is
`Data`, exactly A:AD, with **no additional worksheets**. For multiple tectonic
records, repeat the effective observation's report values/coordinates once per
tectonic record and vary S:U; this supersedes the earlier one-row-per-observation
reporting rule. No duplicate observation is created in the database. Existing
detailed XLSX, CSV and Exchange formats remain separate.
Related: [#68](https://github.com/tinuvael/FieldForge/issues/68),
[#45](https://github.com/tinuvael/FieldForge/issues/45),
[#24](https://github.com/tinuvael/FieldForge/issues/24),
[#4](https://github.com/tinuvael/FieldForge/issues/4).
Issue #68 is closed, but current code and its own B2b specification explicitly leave
application of proposals unimplemented; issue state is not evidence of a write path.

## Workbook evidence and limits

The owner's reference workbook is **`example(2).xlsb`**, with one worksheet,
`Data`, 2,380,086 bytes, SHA-256
`9991f51c1a170a224c219edc9eccfb1da3c54abd4f9f8095192e19bc90b66a97`.
The owner confirmed this filename/hash association during review of PR #75.
The workbook was available and audited; no replacement attachment or filename
confirmation is required. The earlier filename discrepancy was a documentation error.
Neither the workbook, observation names, coordinates nor original observation rows
are included in the repository. Workbook cell text is reference data, not instructions.

Read-only extraction used temporary installations of pyxlsb 1.0.10 and SheetJS CE
0.18.5; neither is an application dependency. All 599,970 cached A:AD cell values,
including blanks, text and IEEE-754 numbers, agreed between the readers using a
typed canonical SHA-256 comparison. Header text, numeric formats, merges and formula
text were inspected separately. No workbook recalculation or saving was performed.
These desktop extraction libraries are not security-qualified iOS import components.

Observed structure:

- Declared used range: `A1:BH19999`; filter: `A4:BH19996`. Neither defines the requested
  reporting width. Required reporting width is **30 columns**, independently A:AD.
- Row 1: `КАРТИРОВАНИЕ ВЫРАБОТОК`; row 2: group headings; row 3: descriptive headings;
  row 4: machine-like short headings; observations begin at row 5.
- Original merges: `A1:AJ1`, `A2:E2`, `F2:H2`, `I2:J2`, `K2:L2`, `M2:R2`, `S2:U2`,
  `V2:AC2`, `AD2:AH2`, `C3:E3`. S2:U2 has a merge but no text at S2.
- A:AD-only output must crop the title merge to A1:AD1 and the rating group to AD2;
  retaining the original AJ/AH extents would create reporting content beyond AD.
  This is an explicit format adaptation, not exact preservation of the entire sheet.
- First observation formats: C:E `0.000`, O `0.00`, AD `0`; other A:AD cells `General`.
  Display precision does not authorize rounding stored or emitted underlying values.
- Extracted widths (Excel character units): A 25.7109375; B/C/E 10.7109375;
  D 13.28515625; F:AD 7.7109375. Extracted row 2 height is 15 pt and rows 4–7 are
  14.1 pt. Row 1/3 heights were not exposed by these readers.
- There are 4,117 rows with a nonempty, non-`-` A value, but only **823 distinct A
  values**. ID is demonstrably not unique. Thousands of later rows contain `-`
  placeholders and formula caches; they must not become imported observations.
- Missing observations commonly use text `-`; actual numeric zeros also occur,
  including azimuth and categorical scores. One spacing and some fault-thickness
  entries are nonnumeric. Import must distinguish missing tokens, valid zeros and
  invalid input; it must not globally coerce text to zero.
- No additional lookup-table worksheet is present. AE:BB contains reported results,
  notes and auxiliary calculations, not required report columns. Some formula
  columns continue through placeholder rows. No cached Excel error cells were
  detected across A:BH, which does not validate the calculations.

SheetJS decoded the formula examples below, including shared-formula references.
pyxlsb supplies cached results, not independently decoded formulas. Thus value
agreement verifies extraction of caches, **not formula correctness or recalculation**.
Font/border/fill/alignment, conditional formatting, validation and printer-setting
fidelity have not been established. No native Excel visual/print inspection was
performed. A sanitized header-only reference or owner-confirmed visual inspection is
needed before claiming full template-format fidelity. No Excel application
compatibility claim follows from successful parsing.

## Exact A:AD mapping

Every column below is structurally required. The template supplies no reliable
required-value/validation specification. `Context` means required external import
context or a required FieldForge identity/location field; `Optional` means retain
blank when absent; `Paired` means validate only if that joint exists. These are
proposed admission rules, not requirements inferred from populated Excel cells.
The owner's subsequent answers approve A = excavation name, O = mean positive
saved J1–J4 spacing, J = actual UCS only and AD = stored final GSI only. The later
clarification fixes exactly one sheet, Data A:AD. Each tectonic record gets its own
report row with the observation's other properties/coordinates repeated; there is
one row with blank S:U when no tectonic record exists. Do not create database points
or select/drop one tectonic record to implement this report-only row expansion.

Property shorthand: `p` = latest effective `MappingObservation`; `r` =
`p.ratings?.rmr89?.input`; `q` = `p.ratings?.bartonQ?.input`; `jN` = interpreted
joint with identifier JN; `fault` = the tectonic record represented by the current
export row. Repeated report rows share one underlying observation identity.
Raw = original input; categorical = explicitly selected description/coefficient;
derived = stored assessment or explicitly defined report projection.

| Column / row-4 header | Original row-3 header | Meaning / units / kind | Proposed source and export | Import / requiredness / unresolved mapping |
| --- | --- | --- | --- | --- |
| A `ID` | Место картирования | Excavation name, text; raw/context | **Owner-approved:** excavation name resolved through `p.excavationID` | A reporting label, not a stable observation identity. Repeated names cannot establish an import match; UUID reconciliation remains separate. |
| B `PK` | Пикетаж | Picket text, documented convention; raw | `p.displayPicket`; original picket, `chainageMeters`, convention and origin stay in storage and separate detailed/Exchange formats | Context for new point; `-` is not chainage zero. Require explicit chainage/convention when missing. No row-number identity. |
| C `X` | Координаты точек замеров (C3:E3 merged) | X, source frame/units; raw | `p.coordinates?.x`, unchanged | Optional; require supplied CRS/axes/XY units/provenance before admitting coordinates. Workbook alone does not establish metres. |
| D `Y` | blank under C3:E3 | Y, source frame/units; raw | `p.coordinates?.y`, unchanged | Optional; same spatial contract as C; validate X/Y together. |
| E `Z` | blank under C3:E3 | Z, metres in FieldForge; raw or provenance-qualified derived | `p.coordinates?.z`; preserve datum and Z origin/plan derivation separately | Optional; unknown stays blank; no horizon/GPS inference during import. |
| F `ROCK` | Сокращенная литология | Project lithology code, exact text; categorical | `p.rock?.code`, never convert to a numeric identifier | Optional; explicit catalogue reconciliation; preserve leading/trailing zeroes, never invent a rock dictionary. |
| G `A45` | Выветривание стенок трещин | Enterprise wall-weathering score, dimensionless; categorical | Explicit `r.basicSelections[weathering]` via existing enterprise mapping, first four categories only | Optional; score alone loses description/method. Enterprise zero means crushed, RMR89 zero decomposed; no automatic equivalence. Independent enterprise zero not currently represented. |
| H `JW` | Обводненность | Q Jw coefficient, dimensionless; categorical | Original `q.jw.value`, not RMR groundwater score | Optional; require category/method/description resolution. Never derive RMR water category from this number. |
| I `A1` | Категория прочности пород | Enterprise strength score, dimensionless; categorical | Existing source: `r.fieldStrength?.rating` (not literal R0–R6 text) | Optional; lab-based score as an alternative needs owner/source approval; score cannot reconstruct exact UCS or field grade without declared method. |
| J `UCS` | Прочность породы, МПа | Uniaxial compressive strength, MPa; raw | **Owner-approved:** `r.strengthMPa` only if `r.strengthTest == .ucs` | Optional; Is(50) stays out; no point-load conversion, interval midpoint or value invented from R0–R6. |
| K `RQD` | Качество породы, % | Original RQD percent; raw | `SpacingRQD(q:rmr:)` precedence: Q original, explicit RMR fallback | Optional; Q/RMR disagreement must be resolved or reported unavailable, never silently choose one. Do not export Q's numerical RQD floor. |
| L `JN` | Количество систем трещин | Q Jn coefficient, dimensionless; categorical | Original `q.jn.value` | Optional; descriptive header is misleading. Not `jointSets.count` and not a value capped at four. |
| M `JR` | Шероховатость стенок трещин | Q Jr coefficient, dimensionless; categorical | Original `q.jr.value` | Optional; not RMR roughness rating; category/rationale required for safe admission. |
| N `JA` | Сцепление стенок трещин | Q Ja alteration coefficient, dimensionless; categorical | Original `q.ja.value` | Optional; header does not make this mechanical cohesion. No MPa/kPa cohesion mapping. |
| O `SD` | Расстояние между трещинами, м | Arithmetic mean spacing, metres; report-derived | **Owner-approved:** arithmetic mean of finite positive saved `spacingMeters` from J1–J4 only | Missing/zero values and J5 are excluded; no participating values means blank. Retain manual/estimated provenance; do not recompute saved spacings from RQD on export. One imported mean cannot be distributed among joint sets without an explicit destination. |
| P `A43` | Раскрытие трещин | Aperture category score, dimensionless; categorical | Explicit `r.basicSelections[aperture]` rating, not `apertureMillimeters` | Optional; score does not mean millimetres. Require category/method resolution, retaining missing raw dimensions. |
| Q `JCON76` | Свойства трещин | Independent 1976 condition score, dimensionless; categorical | `r.jcond76?.rating`, currently stored inside RMR89 input | Optional; explicit JCond76 category, independent of RMR89 condition and Barton Jr/Ja; not a complete RMR76 assessment. |
| R `A42` | Длина трещин | Persistence category score, dimensionless; categorical | Explicit `r.basicSelections[persistence]` rating, not `persistenceMeters` | Optional; do not treat score as metres. Require category/method resolution. |
| S `F_DIP` | Угол падения разлома, ° (trailing space in source) | Fault dip, degrees; interpreted/raw manual | `fault.orientation.validatedTectonic().dipAngle` for this row's tectonic record | **Owner-approved:** one report row per tectonic record, repeating other observation properties/coordinates. No database duplicates or discarded faults. Partial orientation stays partial. |
| T `F_AZI` | Азимут падения разлома, ° | Fault dip direction, degrees with explicit north; interpreted/raw manual | `fault.orientation.validatedTectonic().dipDirection` for the same record | No north conversion or automatic first-record selection. Represent every tectonic record on a separate report row. |
| U `F_THI` | Мощность разлома, м | Fault thickness, metres; raw | `fault.thicknessMeters` for the same record | Optional; S/T/U describe one record together. With no tectonic records emit one observation row with blank S:U. |
| V `J_DIP_1` | Угол падения 1 й системы трещин, ° | J1 dip, degrees; interpretation | J1 representative validated `dipAngle` | Paired; no default 0, retain UUID/evidence/north separately. |
| W `J_AZI_1` | Азимут падения 1 й системы трещин, ° | J1 dip direction, degrees; interpretation | J1 representative validated `dipDirection` | Paired; explicit north and horizontal/vertical convention; no automatic measurement grouping. |
| X `J_DIP_2` | Угол падения 2 й системы трещин, ° | J2 dip, degrees; interpretation | J2 representative validated `dipAngle` | Paired; same rules as J1. |
| Y `J_AZI_2` | Азимут падения 2 й системы трещин, ° | J2 dip direction, degrees; interpretation | J2 representative validated `dipDirection` | Paired; same rules as J1. |
| Z `J_DIP_3` | Угол падения 3 й системы трещин, ° | J3 dip, degrees; interpretation | J3 representative validated `dipAngle` | Paired; same rules as J1. |
| AA `J_AZI_3` | Азимут падения 3 й системы трещин, ° | J3 dip direction, degrees; interpretation | J3 representative validated `dipDirection` | Paired; same rules as J1. |
| AB `J_DIP_4` | Угол падения 4 й системы трещин, ° | J4 dip, degrees; interpretation | J4 representative validated `dipAngle` | Paired; same rules as J1. |
| AC `J_AZI_4` | Азимут падения 4 й системы трещин, ° | J4 dip direction, degrees; interpretation | J4 representative validated `dipDirection` | Paired; same rules as J1. |
| AD `GSI` | GSI | Versioned GSI estimate, dimensionless; interpreted/derived | **Owner-approved:** `p.ratings?.gsi?.finalValue` only; leave blank when absent | Optional; no midpoint of lower/upper bounds or Q correlation. Incoming number cannot fabricate chart position/range/method; needs explicit interpretation support or remains unsupported source data. |

Row-2 groups are A:E `Место картирования`, F:H `Строение`, I:J `Прочность`,
K:L `Структура`, M:R `Свойства трещин`, V:AC `Ориентация трещиноватости`,
AD `Рейтинг массива`. C3:E3 is the only row-3 merge. All original header wording,
including misleading legacy labels, should remain in the report with clarification
in documentation/export guidance; do not silently replace the template headings or
add a reference worksheet to this Data-only export.

A:AD has **no Q, RMR89 or RMR76 total columns**: these are AE:AH in the supplied
book and must not be appended to Data. RMR-related inputs remain G/I/P/Q/R, with
shared raw inputs J/K/O. This regulatory export has no additional source/reference
sheets, hidden metadata sheets or columns beyond AD. Method totals, dates, UUIDs,
revisions, CRS, units, north and provenance stay in storage and separate detailed/
Exchange/backup formats where supported; A:AD cannot carry them completely. It is
not lossless exchange or backup.

The ordinary regulatory `.xlsx` is an owner-facing reporting projection. **FieldForge
Exchange.xlsx** is the separate versioned, lossless interchange representation within
its documented selected-record/schema-8 metadata scope: UUIDs, base revisions,
fingerprints, exact text values and original/history records. It does not include
original photo/DXF bytes or the independent measurement journal and is not a complete
backup. The Data-only report is not an Exchange import baseline. Its repeated
tectonic rows are not separate observation identities; future ordinary import needs
explicit identity/relationship reconciliation rather than one new point per row.
B2b remains read-only.

## Current implementation and confirmed export gaps

| Area | Existing implementation | Gap / reuse boundary |
| --- | --- | --- |
| Regulatory projection | `EnterpriseGeotechnicalWorkbook.tables` returns `Геотех картирование`, `Справочники`, `Исходные данные`; effective rows, history scalar records, preserved originals and optional cells | Wrong sheet count/name/order/width/headings. Replace with only Data A:AD and report-only row expansion per tectonic record. Preserve J5/history in storage and separate detailed/Exchange/backup formats, not extra regulatory sheets. |
| Shared XLSX writer | `MappingXLSXExport.write` / `writeWorkbook`, typed cells, ZIP writer, literal inline strings, formula-safe content, cancellation and field/technical precision policies | Enterprise sheet names hard-coded; flat one-row header, row-1 freeze/filter, generic widths/styles, no merges. Add explicit regulatory layout capability without changing default detailed/Exchange contracts. |
| Current values | Q original coefficients, explicit field A1, JCond76, GSI, selected persistence/aperture/weathering, mean SD and tectonics already exported | Current generic lab-strength output does not restrict to UCS. K chooses Q even on conflict; SD includes J5. These cannot be copied blindly to the new named fields. |
| RMR89 | `RMR89Basic.swift`, `RockMassRatings.swift`, `MappingRatingsForm.swift`, detail view and controlled revision storage | Categorical UI already exists; do not rebuild it. Orientation adjustment and quantitative groundwater reconciliation remain absent. |
| J5 | Codable enum and graph validation, both capture/editor paths, differences, report/export and wedge read models | Preserve persistent enum/validation; restrict routine admission/presentation separately, including correction drafts and Exchange proposals. |
| Exchange B2a | `MappingExchangeExport`, source chunks/fingerprints, text-only XLSX through shared writer | Reuse format and baseline; do not route ordinary A:AD books through its exact-schema parser. |
| Exchange B2b | `ExchangeArchive`, `ExchangeWorkbook`, `ExchangeBaseline`, `ExchangeJSON`, `ExchangeObservationProposal`, preview/coordinator, native Files UI | Secure bounded read-only preparation and seven classifications already exist. No Apply, durable replay mapping, write transaction or ordinary workbook adapter. |
| Persistence / backup | Schema 8 `MappingJournal`, `FileMappingStore`, FIFO `MappingStorageOwner`, immutable originals/revisions, `.previous`, external-change checks; B1a/B1b backup/restore | No durable import ledger. Existing ephemeral `generationID` is not restart identity. Ledger must participate in recovery and complete backup/restore before B2c. |

The 88-column minimum follows 39 leading + 25 J-set + 24 trailing columns in
`EnterpriseGeotechnicalWorkbook`; fault columns are variable. The current source
sheet includes revisions, measurements and photo metadata, not original photo/DXF
bytes. That is existing behavior, superseded for the new Data-only regulatory profile.
Detailed `MappingFieldWorkbook`, relational CSV, photo packages and
`FieldForge Exchange.xlsx` retain their contracts and preservation roles.

Engineering numbers retain full values in storage and separate lossless formats.
Excel numeric cells
have approximately 15 significant digits; the current field-numeric writer bypasses
its technical-sheet text safeguard. For C:E and any higher-precision fields, Stage 2
must explicitly select exact-text cells where required or expose the limitation and
exact values in the separate formats. No companion columns/sheets may be added to
this Data-only export. Never claim an Excel numeric cell preserves arbitrary Double
precision. Template display formats alone are insufficient.

## RMR76 / RMR89 methodology and workbook discrepancies

**Implementation gate:** do not implement RMR76 scoring until the complete
edition-specific rating **and applicability** tables have been verified against
published references. Partial reproductions, workbook formulas, a matching benchmark
total or owner selection of a desired workflow cannot replace that verification.
Verify the full strength/test, RQD, spacing, condition, groundwater and
application-specific orientation rules, including boundaries and special cases,
before creating executable scores or categories.

### Owner-specified enterprise category descriptions

In the subsequent specification reply the owner supplied these intended categories.
This records their source as **owner-entered requirements**, not independently
verified published RMR76 tables or new executable engineering rules.

| Field | Owner-specified categories and scores |
| --- | --- |
| A42, persistence / length | <1 m → 6; 1–3 m → 4; 3–10 m → 2; 10–20 m → 1; >20 m → 0 |
| A43, aperture | No aperture → 6; nonzero <0.1 mm → 5; 0.1–1 mm → 4; 1–5 mm → 1; >5 mm → 0 |
| A45, wall alteration | None → 6; slightly weathered → 5; moderately weathered → 3; highly weathered → 1; crushed → 0 |
| A1, intact strength | <1 MPa → 0; 1–5 MPa → 1; 5–25 MPa → 2; 25–50 MPa → 4; 50–100 MPa → 7; 100–250 MPa → 12; >250 MPa → 15 |

The stated ranges share endpoints. Preserve explicit category selection; do not
invent half-open intervals or automatic boundary precedence. A1's measured-UCS
versus field-grade source/precedence still needs a precise contract before changing
export behavior. A45 crushed=0 remains distinct from RMR89 decomposed=0, and the
current model has no independent enterprise crushed-wall category. No existing
assessment or historical value is reinterpreted by recording these requirements.

The owner also suggested checking template formulas linking RMR and Barton.
The formula audit below already identifies such expressions and their limitations:
inferred Jr/Ja-based condition ratings are not approved substitutions for geological
RMR categories. No Q↔RMR conversion or RMR76 scoring is authorized by this suggestion.

### Published reference register (accessed 2026-11-07)

1. Bieniawski, Z.T. (1976), *Rock Mass Classification in Rock Engineering*,
   Symposium on Exploration for Rock Engineering, vol. 1, pp. 97–106, Balkema.
   Bibliography located; the complete original paper was **not** available for audit.
2. Bieniawski, Z.T. (1989), *Engineering Rock Mass Classifications*, Wiley,
   ISBN 0-471-60172-1. The [public EIS extract](https://www.resolutionmineeis.us/sites/default/files/references/bieniawski-1989.pdf)
   contains title/contents only. A separate [250-page scanned copy](https://iem.ca/pdf/resources/Engineering%20Rock%20Mass%20Classifications_%20A%20Complete%20Manual%20for%20Engineers%20and%20Geologists%20in%20Mining%2C%20Civil%2C%20and%20Petroleum%20Engineering.pdf)
   was downloaded temporarily and rendered for visual inspection: Table 4.1 A–D,
   printed pp. 54–55 (PDF 59–60), Chart E, printed p. 58 (PDF 63), and Table 4.2,
   printed p. 59 (PDF 64). These verify the core categorical scores and the filling
   caveat against the original book. Chart E and Table 4.2 are separate from Table
   4.1; the later reproduction combines them under E/F. Scan SHA-256:
   `173c47db7cc92dbd5faa7e65d55fdd313efee51a41e9350b9bd6aea9d3cae743`.
   No source PDF or page images are committed; this is not a full-book applicability audit.
3. Hoek, *Practical Rock Engineering*, chapter *Rock mass classification*,
   [Table 4 A/B/C/E/F, printed pp. 9–10](https://www.rocscience.com/assets/resources/learning/hoek/Practical-Rock-Engineering-Chapter-3-Rock-Mass-Classification.pdf).
   Author-hosted engineering reproduction of RMR89 and its worked example; used by
   the existing evaluator/tests. Does not replace complete original-method review.
4. Hoek, Kaiser & Bawden (1995), *Support of Underground Excavations in Hard Rock*,
   [§8.5, printed p. 103, PDF page 169, Table 8.5 and edition-comparison example](https://www.rocscience.com/assets/resources/learning/hoek/Support-of-Underground-Excavations-in-Hard-Rock.pdf#page=169).
   Author-hosted reproduction of the first four 1976 parameters; groundwater and
   full orientation tables are not reproduced there. The nearby prose mistakenly
   calls this Table 8.3; identify the actual caption 8.5.
5. Hoek, Carter & Diederichs (2013), ARMA 13-672, *Quantification of the Geological
   Strength Index Chart*, [Appendix 1, Tables 1–3, PDF page 9](https://www.rocscience.com/assets/resources/learning/hoek/Quantification-of-the-GSI-Chart-2013.pdf#page=9).
   Independently supports stored JCond76 and separation from JCond89/Jr/Ja.
6. Private enterprise methodology: repository documentation records Appendix 6,
   Tables 3/4/6 and DOCX SHA-256
   `c759076c8f7f22c9ba112ad71ce0c01650abf72760841baf881c8fe94b361ee9`.
   The original document was not supplied in this task, so earlier verification is
   historical evidence, not a new check of its title/revision or regulatory status.

Compact edition comparison from references 2–5 (not a new executable rating table):

| Parameter | RMR76 | RMR89 |
| --- | --- | --- |
| Strength top band | Is(50) >8 MPa / UCS >200 MPa | Is(50) >10 MPa / UCS >250 MPa |
| Lower UCS bands | 10–25, 3–10, 1–3 MPa | 5–25, 1–5, <1 MPa |
| RQD scores | 20/17/13/8/3 | 20/17/13/8/3 |
| Spacing | >3, 1–3, 0.3–1, 0.05–0.3, <0.05 m; 30/25/20/10/5 | >2, 0.6–2, 0.2–0.6, 0.06–0.2, <0.06 m; 20/15/10/8/5 |
| Overall condition | 25/20/12/6/0; hard/soft walls | 30/25/20/10/0; weathering descriptions; detailed E alternative |
| Groundwater | Dry = 10 in published comparison; remaining categories need original source | Dry/damp/wet/dripping/flowing = 15/10/7/4/0; alternative quantitative descriptions |
| Orientation | Very favourable = 0 in comparison; full application tables not verified | Separate application-dependent adjustment; existing app leaves it uncalculated |

Existing RMR89 stores selected category identifiers, original numeric/free-text inputs,
method version, timestamp, components, missing items and optional basic total.
Versions are `input-only-v1`, `basic-categories-v1` and
`basic-categories-field-strength-v2` under the `Bieniawski-RMR89/` prefix.
Stored assessments revalidate against the appropriate method. JCond76 has its own
category/rating/version but lives inside `RMR89Input`; it is not added to the total.
There is no `RMR76Input`, independent assessment, evaluator or full RMR76 UI.

All requested RMR89 selectors except orientation adjustment are already present:
strength basis/grade, RQD, spacing, persistence, aperture, roughness, infill,
weathering, groundwater, and conditional overall A.4. Raw inflow/pressure values are
validated numerically but not reconciled with the selected groundwater band.
Application/orientation text is stored but does not calculate a correction.
The evaluator correctly refuses absent categories and low Is(50) conversion, keeps
explicit shared-endpoint choices, and uses A.4 for filling rather than blindly adding E.
Review its conservative hard-filling >5 mm refusal and requirement for E selections
even when A.4 is used before broadening the supported method. Rating arrays alone
do not establish all special-case applicability.

Independent benchmark candidates:

- RMR89: reference 3 example gives components 12 + 13 + 10 + 22 + 7 = **64 basic**;
  condition = 4 + 4 + 3 + 6 + 5. With the explicitly specified fair tunnel orientation,
  adjustment −5 yields **59 adjusted**. Existing `FinalFieldPolishTests` checks 64 and
  does not apply −5; orientation implementation needs a separate expected-value test.
- RMR76: reference 4 edition-comparison example gives 12 + 13 + 20 + 20 + 10 =
  **75 basic**, with explicit zero orientation adjustment. Its 300 mm shared endpoint
  must remain an explicit published-example selection. Add this independent case
  after the complete 1976 table/source contract is approved; no RMR76 test exists now.

Formula audit findings, independent of cached results:

- `AK5 = IF(AF5="-","-",9*LN(AF5)+44)` is copied/referenced into later GSI cells.
  It uses Q-based correlation, not the app's versioned graphical GSI interpretation.
  No such correlation is authorized for regulatory export.
- `AP5`, `AQ5` and `BB5` infer RMR condition subcomponents using Q Jr/Ja and other
  category scores. This is not direct selection of published RMR descriptions.
- `AX5` sums inferred condition components, A45 and a manually stored orientation
  term `AW5`. It therefore cannot be equated with the app's stored basic RMR89.
- `AY5 = IF(OR(AW5="-",R5="-",AV5="-"),"-",AW5+AN5+AT5+AU5+AV5+R5)`.
  R is labelled A42 persistence; Q is labelled JCON76. The formula uses **R**, not Q,
  as the condition-like term. This is an explicit header/formula inconsistency;
  do not silently repair it and call the result published RMR76.
- `AT5 = I5` reuses the strength score across editions despite different strength
  thresholds. `AL5`/`AV5` map Q Jw numerically to RMR water ratings; neither proves
  the corresponding original RMR water observations.
- `AZ5` calculates Q′ from RQD/Jn × Jr/Ja; `BA5` adds Jw with denominator fixed to 1.
  The latter embeds SRF=1 without an explicit SRF column in A:AD. Never substitute
  that for the existing method-qualified Q evaluation.
- Formula guards check particular dash/space tokens, not all missing/invalid inputs.
  Earlier report cells include hard-coded cached-like values while later ones link
  to auxiliaries. No inference about authorship, intended correction or valid
  engineering methodology is drawn from these differences.

Stage 3 must keep methods independent, preserve historical assessment versions and
their results, record descriptions/IDs/scores, and expose basic/adjusted/missing
states. No reinterpretation on load, Q substitution, Is(50)→UCS conversion, inferred
drive orientation, mechanics or support recommendations are authorized here.

## Legacy J5 compatibility assessment

Retain `JointSetIdentifier.J5`, Codable spelling and graph limit of five for historical
decoding/validation. Removing the enum or tightening global validation to four would
make valid schema-8 observations, revision chains and restored backups unreadable.
Do not change `allCases` to hide persistent values; introduce an explicit routine
selection J1–J4 and apply it only where that policy is required.

Audit of every production `JointSetIdentifier.allCases` use at this revision:

| Site | Treatment in a later J1–J4 PR |
| --- | --- |
| `MappingGeology.swift` / `MappingDraft.addJointSet` | Choose new identifiers from J1–J4; guard direct new-set acceptance too, not only the button. Keep decoding/legacy graph validation. |
| `MappingJointSetsSection.swift` | Main capture add/edit/evidence assignment uses four; remove `/5`/five-limit assumptions. |
| `MappingObservationDifference.swift` | Continue enumerating all persisted identifiers so J5 changes/history cannot disappear from comparisons. |
| `MappingFieldWorkbook.swift` (headers and row population) | Preserve detailed export J5 contract; clearly historical, independent of the new regulatory sheet. |
| `EnterpriseGeotechnicalWorkbook.swift` (headers and row population) | Replace regulatory projection with Data only and explicit J1–J4; use approved J1–J4 SD mean. Keep J5/history in storage and separate detailed/Exchange/backup formats. |

Additional dependencies not using `allCases`:

- `MappingGeologyForm` correction/older editor has `/5`, add limits, editable existing
  rows and delete buttons. Keep historical J5 attached while editing other fields;
  show J5 read-only under historical data. A hidden row must not be omitted from the
  correction snapshot or re-estimated when RQD changes.
- `MappingDraft.newJointSet`, `acceptJointSet`, `JointSetDraft.record`, correction
  admission and `updateSpacingEstimates` need distinct new-versus-preserved policy.
  New J5 through a non-UI route must be rejected; unchanged legacy J5 must survive.
- Exchange uses raw enum parsing and iterates actual sets: unchanged J5, source
  baselines and evidence stay readable; proposals creating/modifying J5 should be
  unsupported under routine policy. Preserve the entire legacy J5 in candidate
  snapshots. Do not reject an otherwise unchanged historic workbook.
- CSV/Exchange/source flattening, backup/restore and graph validation must preserve
  J5 UUID, revision, spacing/provenance, representative and measurement links.
- `WedgeMappingSource` iterates actual sets; `WedgesView` currently offers J5 for
  selection. Routine choices become J1–J4; historic J5 stays visible in read-only
  advanced evidence. Do not alter orientation geometry or infer mechanics.
- DXF coordinate/plan services have no direct J5 enum dependency. Their markers open
  the shared effective point, so that detail/history path must still expose J5.
  Photo contexts remain tied to the exact original point revision, including J5.
- Tests depending on all five: `P32GeologyTests`, `FinalFieldPolishTests`,
  `EnterpriseGeotechnicalTests`, `ThirdIPhoneReviewTests`,
  `MappingExchangeExportTests`, `MappingExchangePreviewTests`,
  `OfflineBackupTests`, `WedgeW1Tests`, and storage benchmark fixtures. Keep explicit
  legacy-five fixtures; change routine-capture expectations separately. No benchmark
  or fixture generation is needed for this audit.

Required focused coverage: new J5 refused through capture/acceptance/correction/import;
legacy J5 loads, survives unrelated correction and RQD edits unchanged, appears in
history/source/Exchange/CSV, and survives complete backup/restore with original
measurement evidence. No renumbering, merging, deletion, schema change or migration.

## Import architecture and field-resolution proposal

Reuse B2b's Files lifecycle, security-scoped coordinated bounded read, secure ZIP/XML,
canonical baseline reconstruction, per-point candidates/deltas, generation checks and
publication ownership. It already classifies new/unchanged/correction/duplicate/
conflict/invalid/unsupported. The current `Change` contains table, record, field,
before and after; the future resolution view must join point/location, source workbook,
base revision/fingerprint, local revision and method provenance explicitly.

Do not relax the Exchange text-only authoritative-cell contract to accept ordinary
numeric workbooks. Use a separate A:AD adapter and format discriminator, sharing
bounded archive/XML infrastructure where appropriate. Exchange currently rejects
formulas/caches, numeric/date coercion, external links/macros, unsafe ZIP/XML, missing
baselines and unsupported evidence changes. Preserve those guarantees.

Proposed pipeline:

1. Read `.xlsx` without mutation. Detect Exchange versus explicitly chosen ordinary
   Data profile. Preserve filename/hash, conversion provenance and parser version.
   Reject `.xlsb` with an honest conversion instruction until a separate native
   parser/security/fixture project is qualified. Desktop audit parsing is not support.
2. Normalize into detached source records and diagnostics, preserving source cells,
   raw strings, explicit blanks, numeric values and units. Empty/dash-only template
   rows are not observations. Require a chosen project/horizon/excavation, field date
   and timezone, picket convention/origin, north and spatial metadata absent from Data.
   Do not substitute import time for the observation date or GPS for location.
3. Exchange identities use UUID + base revision/fingerprint and immutable evidence.
   Ordinary ID/PK/XYZ only generate **candidates**. Regulatory rows repeated for
   tectonic records must be reconciled to one parent observation with its multiple
   structures, never blindly admitted as one point per row or silently grouped by
   shared properties/coordinates. Ask the reviewer to create a new
   observation, explicitly bind to a local UUID, or skip. Duplicate identical rows
   can also be distinct observations; never silently collapse ambiguous identity.
4. Display complete field comparisons, grouped by observation UUID/client token and
   location: current phone value, incoming value, local/base revision, source workbook
   and method, conflicts and missing parents. Offer keep local, accept incoming as a
   controlled correction, or skip observation. Source-only unsupported fields remain
   visible; no unsupported derived value enters an existing assessment silently.
5. For stale Exchange bases, rebase explicitly against the newest committed snapshot.
   Three-way comparison may identify unchanged/concurrent fields, but never applies
   last-write-wins. Recheck combined-field/domain validity after choices (paired
   coordinates/orientations, rating basis/categories, method/provenance and parents).
   Empty incoming fields mean no proposal by default; clearing an existing optional
   value is a separate explicit decision, not destructive blank replacement.
6. Confirm the **entire resolved batch**, including skips and resulting field deltas.
   Capture a semantic digest over identities, bases, choices, typed values, units and
   context. A later generation change invalidates confirmation and requires preview
   regeneration. UI confirmation authorizes this exact batch only.
7. Admit through `MappingStorageOwner` FIFO. In its synchronous transaction re-read
   current generation, originals/history/fingerprints, parent identities and proposed
   UUID collisions. Allocate admission IDs/times and append revisions; new spreadsheet
   observations are external/manual evidence, never fabricated sensor measurements.
   Validate the complete proposed graph before any durable publication.
8. Commit graph, audit and replay state as one recoverable unit; publish only after
   successful durable commit. Existing observations/measurements/photos/DXF stay
   immutable. Cancellation before admission is a no-op; after admission follow the
   owner's existing rule of reconciling the committed result rather than claiming
   cancellation undid a write. Failure recovers the whole batch or blocks further writes.

Replay/audit proposal:

- Exchange: preserve `(workbook_id, client_record_id) → point_id`, and an operation
  token for corrections mapping to the admitted revision. Token + accepted semantic
  digest replays as a no-op; same token with changed semantics is a conflict.
- Ordinary books: exact normalized batch + context replay can be recognized using a
  durable import receipt. Persist reviewer-established source-to-point bindings and
  stable admission tokens. Row numbers only locate source cells; never identify records.
  A colleague-edited anonymous book cannot reliably retain observation identity across
  edits/sorts without metadata. Require explicit reconciliation again, or return a
  separate metadata sheet/companion Exchange file with stable tokens for subsequent edits.
  Sorting must not create new observations, and a repeated subset must not bypass
  stored source bindings. Ambiguity remains visible instead of a false no-duplicate claim.
- Retain accepted/kept/skipped deltas, source/export metadata, parser/format/method
  versions, base/local revision identities, reviewer/reason, import/admission time,
  resulting UUIDs/revisions and complete batch digest. Hashes are integrity and replay
  tools, not authenticated colleague identity. Retain original imported source evidence
  under an explicitly reviewed storage/backup policy, without copying private data to git.

### B2c storage design gate

Schema 8 has no ledger field. An independently saved receipt sidecar cannot guarantee
idempotence: a crash between journal and sidecar saves admits a point twice or reports
an operation applied without its graph. Existing `.previous` alone cannot solve this.

Before implementing B2c, specify and review one of:

- A ledger stored in the same authoritative commit representation as the graph, with
  an explicit owner decision about format compatibility/version. Adding an optional
  schema-8 field is not automatically safe: older writers may discard it, and B2b's
  strict baseline reprojection/backup validation must preserve it.
- A recoverable transaction manifest coupling before/after graph hashes, the complete
  ledger/audit update and commit state. All readers/writers, startup recovery, `.previous`,
  external-change guards and complete backup/restore must enforce that contract.
  This is materially more work than an independent sidecar; no atomicity claim is made
  until interrupted-commit/relaunch tests pass.

Do not change schema 8, add migrations or build either option in this audit.
The design must establish necessity before requesting a schema exception. Protect the
independent original-measurement journal's existing compatibility and backups.

### XLSB conversion boundary

Proposed desktop workflow: preserve original XLSB; open a copy in Excel, disable
untrusted active content/external updates, save a separate `.xlsx`; compare A:AD
headings, cell types, blanks and numeric precision with the original. For ordinary
imports, export a reviewed **values-only** A:AD copy, retaining the original formulas
in the untouched source file and recording conversion provenance. Formula results
must not enter as verified geological observations. Do not apply values-only editing
to protected Exchange baselines. The workbook's formula-derived GSI should remain
unsupported unless independently admitted as an explicit interpretation.

This is a proposed conversion procedure, not a validated converter: no Excel save or
converted XLSX was supplied/tested here. Stage 4 must test an actual converted synthetic
fixture, locale/precision/date handling, formula/external-part rejection and its
ordinary numeric-cell policy before advertising this workflow as supported.

## Focused PR sequence and decision gates

| Stage / PR | Deliverable | Gate / targeted validation |
| --- | --- | --- |
| 1 — this documentation PR | Exact mapping, inventory, published-source comparison, J5/replay design, questions | Read-only two-reader workbook check; source/diff/link review. No application changes. |
| 2 — regulatory Data export | Exactly one sheet Data A:AD, four-row header, merges/formats, effective observations, explicit blanks and one report row per tectonic record | Resolve remaining value/precision/spatial policies. Synthetic tests for one sheet, all 30 headers/order/values, no AE:BB, J1–J4, approved SD mean, missing/zero, revisions/multiple points and 0/1/multiple tectonic records with repeated properties but no database duplicates; unchanged detailed/CSV/Exchange contracts. One targeted test run and Simulator compile; independently read generated XLSX. Native Excel visual acceptance separately recorded. |
| 3a — routine J1–J4 | Capture/correction/assignment/wedge controls and policy guards; read-only historical J5 | Retain schema 8/global five-value decoding; targeted admission/legacy revision/Exchange/backup round-trips and one Simulator compile. Do not rewrite historical evidence or fixtures to erase J5. |
| 3b — RMR89 refinement | Reuse selectors/evaluator; verified water/condition rules and explicitly supported orientation adjustment | Complete published source/applicability pack; preserve old method versions. Independent expected components/boundaries/missing inputs/basic-vs-adjusted/no-Q-substitution tests and one Simulator compile. |
| 3c — independent RMR76 | Separate versioned categories, assessment/storage/UI/export integration | Complete 1976 water/orientation/low-strength/endpoint sources and storage/old-writer preservation decision. Independent benchmark 75 plus boundaries and missing/invalid tests; one Simulator compile. No cloned RMR89 weights. |
| 4a — B2c design | Owner-reviewed atomic ledger/recovery/audit/backup specification | No Apply implementation before this gate; resolve schema/compatibility necessity explicitly. |
| 4b — confirmed Exchange writes | Per-field resolutions, whole-batch approval and owner-owned atomic admission | Target new/unchanged/correction/duplicate/stale/conflicting/invalid-parent/invalid-unit cases, cancellation, IO failures, replay and restart/fault injection; one Simulator compile. |
| 4c — ordinary Data import | Separate adapter, explicit identity/context/category reconciliation and reviewed XLSX conversion | Same durability rules; missing optional fields, ambiguous identity, reordered/duplicate rows, numeric precision, no-metadata repeated edits/replays. One focused suite and Simulator compile. Real Files-provider/integrated acceptance stays under #24. |

No broad refactor, full regression, performance/stress benchmark, DXF fixture generator,
device operation, data reset or automatic PR merge belongs to this audit. Engineering
implementation retains independent expected-value tests. No test/build run is claimed
for this documentation-only change; implementation PRs require targeted tests and one
Simulator build each. Full final qualification remains separate.

## Remaining owner decisions and source requirements

Already settled: the reference is `example(2).xlsb` with the hash above; primary
regulatory sheet `Data`, exactly A:AD; four routine sets J1–J4; preservation of
historical J5; independent RMR89/RMR76; separate regulatory and Exchange formats.
The subsequent owner answers also settle A = excavation name, O = mean positive
saved J1–J4 SD (no valid values → blank), J = actual UCS only, AD = stored final GSI
only. The later answers settle exactly one worksheet, Data A:AD, and one report row
per tectonic record with repeated observation properties/coordinates (one blank-S:U
row if no tectonics). This replaces the earlier one-row-per-observation export rule;
it never duplicates database observations. The supplied enterprise category
descriptions are recorded above with their owner-entered provenance. These settled
requirements do not need reconfirmation. The following items remain open:

1. **Other report value policies:** decide whether I/A1 is field-strength-only or
   also admits a verified measured-UCS score, including precedence; establish endpoint
   handling for automatic categorization if requested and a separate A45 crushed-wall
   input if needed; define how conflicting Q/RMR RQD inputs are exposed/resolved.
   J/UCS may contain only actual UCS, never an implicit Is(50) conversion or invented
   field-grade midpoint. Missing values must not become zero.
2. **Layout and precision:** Data-only and omission of all supplementary sheets are
   settled. Confirm merge
   cropping at AD and exact-text precision exceptions. Resolve remaining visual
   fidelity through a sanitized header/style reference or owner inspection. The
   primary Data name and 30-column width are already fixed.
3. **Spatial/context reporting and ordinary import:** decide how retained
   CRS/units/axes/north/provenance are exposed outside the Data-only workbook and which unresolved or mixed frames
   cause warnings/refusal. Ordinary imports also need explicit parent/date/timezone,
   picket-convention and spatial context absent from A:AD. No conversion or inferred
   underground location is permitted.
4. **Engineering reference pack and scope:** locate the enterprise DOCX/title/revision
   and complete edition-specific published method/applicability tables; select the
   supported applications and groundwater/orientation workflows. The original 1989
   core tables were checked; complete 1976 verification remains outstanding. Owner
   approval cannot waive the RMR76 source-verification gate above.
5. **Storage/compatibility design:** review separate RMR76 storage and atomic durable
   import ledger/audit/recovery/backup representation, including preservation by old
   writers. Schema 8 remains unchanged; any independently justified exception needs
   a separate owner decision. An independently saved receipt is insufficient.
6. **Ordinary-import reconciliation:** choose a separate companion/Exchange workflow or
   repeated explicit identity resolution for anonymous colleague-edited books;
   approve the durable binding/replay policy and handling of explicit clears and
   unsupported derived values, including a destination for an imported aggregate SD
   and explicit reconciliation of repeated tectonic rows to one parent observation.
   Neither row numbers nor ID/PK/coordinates alone
   establish identity. The conversion procedure remains unqualified until tested.

This review authorizes documentation corrections only. Do not start Stage 2 or any
other implementation from PR #75, and do not merge automatically. A later reporting
PR requires resolution of its material decisions and separate implementation
authorization; later engineering and import gates remain independent.
