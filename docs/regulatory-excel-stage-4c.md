# Regulatory Excel Data A:AD round-trip

In **Журнал → Импорт Excel**, select **Регламент · Data A:AD** and choose the
edited XLSX. The preview reports workbook rows, matched observations, missing
matches, duplicates, unsupported edits and conflicts. Open an observation to
review its project, horizon, excavation, field date, UUID, Excel row numbers and
before/after values. Mark the changes to accept and confirm. The final report
shows applied, previously applied, skipped, rejected and pending work.

## Export and matching

The regulatory exporter still writes `FieldForge-Geotechnical.xlsx` with exactly
one visible sheet, `Data`, the four existing header rows, columns A:AD and the
existing layout, styles and values. The optional **Добавить файл сопоставления
для импорта** setting shares a second file, `FieldForge-Geotechnical-Matching.json`.
Keep the JSON beside the workbook, edit only the workbook, then select both files
in the import screen. The default export is still a single XLSX. With the same
export snapshot, tests compare the XLSX byte for byte with and without the
companion.

The companion records the export UUID and time, and binds the original Excel row
range to the observation UUID and context, revision/version and observation and
graph fingerprints. It contains no attachment bytes or editable values. Keep
the rows in their original positions. The importer checks the workbook UUID if
the editor retained it and validates the binding against the local journal and
the complete read-only projection, including all fault rows. If the editor
dropped the workbook UUID, confirm the companion's target explicitly. A row number
locates a binding and its diagnostics. The binding and journal supply identity.
Observations with indistinguishable common read-only report values require
separate exports. Treat the companion as part of the original export and keep
it unedited. Fingerprints check consistency with the journal and identify replay.

Without a companion, the exact excavation name and display picket shortlist
candidates. Choose the observation even when there is a single candidate.
Coordinates and other report values are checked after selection. Compare the
workbook with the current journal before approving, since an anonymous file
cannot establish which journal revision was originally edited. Retain a
companion to detect changes made in the journal between export and import.
Stage 4c updates existing observations. Unmatched rows are reported and
require reconciliation in the journal.

For observations with several tectonic structures, keep the full set of rows.
Make the same ROCK, A45 or A1 edit on each row. The group must match the
projected S:U rows and yield one consistent proposal, which produces one
revision. Duplicate rows, missing fault rows and differing edits block that
observation. For another edit cycle, re-export the accepted journal values and
keep the newly generated companion with the new workbook.

## Exact column contract

Row 4 gives the keys below. The descriptive headers, including the trailing
space in S3, follow the [audited reference](regulatory-excel-audit.md#exact-aad-mapping).
`p` is the effective observation, `q` and `r` are the saved Barton Q and RMR89
inputs, and `J1`–`J4` are the saved representative interpretations.

Read-only cells must equal the typed FieldForge projection, including missing
values. The allowed values below describe that projection. They do not admit
new measurements, orientations, interpretations or assessment inputs.
In the editable cells, blank or the legacy dash `-` keeps the current value.
Use text `#CLEAR` to remove a value explicitly. Zero is a numeric category
where listed. Category values are numeric Excel cells. ROCK is text.

| Column and key | FieldForge source | Type, units and allowed values | Import |
| --- | --- | --- | --- |
| A `ID` | Excavation name through `p.excavationID` | Exact text, existing name | Read-only, required match context |
| B `PK` | `p.displayPicket` | Exact display text in the saved convention | Read-only, required match context |
| C `X` | `p.coordinates?.x` | Finite number in the saved XY units and axes, or blank | Read-only, exact numeric comparison |
| D `Y` | `p.coordinates?.y` | Finite number in the saved XY units and axes, or blank | Read-only, exact numeric comparison |
| E `Z` | `p.coordinates?.z` | Finite elevation in metres in the saved datum, or blank | Read-only, exact numeric comparison |
| F `ROCK` | `p.rock?.code` | Exact decimal-looking **text** code, including leading/trailing zeroes, or blank | Editable, new code must exist in the target project's catalogue. Preserve name for an unchanged code. `#CLEAR` removes the point's lithology selection |
| G `A45` | `p.ratings?.regulatory?.wallAlteration` with equivalent RMR89 weathering fallback | Dimensionless score. 6 unweathered, 5 slight, 3 moderate, 1 high, 0 crushed, or blank | Editable independent reporting choice. `#CLEAR` requires the resulting projection to be blank. RMR89 weathering stays intact |
| H `JW` | `q.jw.value` | Saved numeric Q water coefficient, dimensionless, or blank | Read-only, exact saved coefficient. RMR groundwater is independent |
| I `A1` | `p.ratings?.regulatory?.strength` with RMR field-grade fallback | Dimensionless score. 0 <1 MPa, 1 for 1–5, 2 for 5–25, 4 for 25–50, 7 for 50–100, 12 for 100–250, 15 >250, or blank | Editable independent reporting band. `#CLEAR` requires the resulting projection to be blank. Field grade and laboratory values stay intact |
| J `UCS` | `r.strengthMPa` for `r.strengthTest == .ucs` | Saved UCS in MPa, or blank | Read-only, exact numeric comparison. Is(50) stays out |
| K `RQD` | `SpacingRQD(q:rmr:)` from original inputs | Number 0–100%, or blank if absent or sources disagree | Read-only, exact numeric comparison. Q's numerical floor stays out |
| L `JN` | `q.jn.value` | Saved numeric Q joint-set-number coefficient, dimensionless, or blank | Read-only, exact saved coefficient |
| M `JR` | `q.jr.value` | Saved numeric Q roughness coefficient, dimensionless, or blank | Read-only, exact saved coefficient |
| N `JA` | `q.ja.value` | Saved numeric Q alteration coefficient, dimensionless, or blank | Read-only, exact saved coefficient |
| O `SD` | `JointSpacingMean` of saved positive J1–J4 spacings | Positive derived number in metres, or blank | Read-only, exact projected mean. Individual spacings remain as saved |
| P `A43` | RMR89 aperture selection in `r.basicSelections` | Dimensionless score 6, 5, 4, 1 or 0, or blank | Read-only rating, exact projection |
| Q `JCON76` | `r.jcond76?.rating` | Dimensionless historical score 25, 20, 12, 6 or 0, or blank | Read-only rating, exact projection. Historical method and category stay intact |
| R `A42` | RMR89 persistence selection in `r.basicSelections` | Dimensionless score 6, 4, 2, 1 or 0, or blank | Read-only rating, exact projection |
| S `F_DIP` | Current row's tectonic orientation, validated dip angle | 0–90 degrees, or blank | Read-only, exact S:U row comparison |
| T `F_AZI` | Current row's tectonic orientation, validated dip direction | 0 to <360 degrees in the saved north reference, or blank | Read-only, exact S:U row comparison |
| U `F_THI` | Current row's tectonic `thicknessMeters` | Nonnegative finite metres, or blank | Read-only, exact S:U row comparison |
| V `J_DIP_1` | J1 representative dip angle | 0–90 degrees, or blank | Read-only, exact projection |
| W `J_AZI_1` | J1 representative dip direction | 0 to <360 degrees in the saved north reference, or blank | Read-only, exact projection |
| X `J_DIP_2` | J2 representative dip angle | 0–90 degrees, or blank | Read-only, exact projection |
| Y `J_AZI_2` | J2 representative dip direction | 0 to <360 degrees in the saved north reference, or blank | Read-only, exact projection |
| Z `J_DIP_3` | J3 representative dip angle | 0–90 degrees, or blank | Read-only, exact projection |
| AA `J_AZI_3` | J3 representative dip direction | 0 to <360 degrees in the saved north reference, or blank | Read-only, exact projection |
| AB `J_DIP_4` | J4 representative dip angle | 0–90 degrees, or blank | Read-only, exact projection |
| AC `J_AZI_4` | J4 representative dip direction | 0 to <360 degrees in the saved north reference, or blank | Read-only, exact projection |
| AD `GSI` | `p.ratings?.gsi?.finalValue` | Saved final estimate, dimensionless, or blank | Read-only, exact projection. GSI chart position, range and method stay intact |

Source and version details for the two editable ratings and the shared
A42/A43 projections are in the [field category contract](enterprise-geotechnical.md#regulatory-field-categories-stage-3a).
A45 zero is the owner-defined crushed-wall selection. A1 scores select field
bands. The accepted changes preserve Q, RMR89, GSI, JCond76, J5, raw
measurements, photographs, tectonic structures and earlier snapshots.
There is no assessment recalculation.

## Validation, commit and recovery

The reader uses Stage 4b's bounded ZIP/XML validation and accepts the
single-sheet regulatory structure and its header merges. It checks all four
header rows and reports the addresses of missing, duplicate or reordered
headings. Nonempty cells beyond AD are rejected. Inline and shared strings
preserve text codes. Date/percent/custom unit formats, formula cells and cached
formula results, numeric coercion of text identifiers, unsupported cell types
and unrepresentable numeric values are refused. When an editor rounds an
exported protected number to its 15-significant-digit limit, the changed cell
blocks that observation. Recover the exact value from the source export. Empty
rows and rows consisting entirely of blank/dash placeholders are ignored.

The Stage 4b confirmation path re-reads the XLSX and compares its SHA-256 to
the preview. On the storage queue, each approved observation is checked against
its current revision, content and graph before admission. Stage 4a persists
the pending intent, then commits the appended revision and receipt together in
the schema-8 journal. Reopening the same workbook recovers a pending intent
against its original approved snapshot or offers rejection if the journal
changed. Applied operations replay without another revision. Rows in other
observations can succeed independently. The mapping journal carries the ledger
through the existing backup workflow.

## Reference and verification limits

The local copy of `example(2).xlsb` matched SHA-256
`9991f51c1a170a224c219edc9eccfb1da3c54abd4f9f8095192e19bc90b66a97`.
Read-only extraction verified the `Data` header values across A:AD. The
[Stage 1 audit](regulatory-excel-audit.md#workbook-evidence-and-limits) records
the broader original used range, formula caches and template differences.
The original file remains private. FieldForge imports XLSX only. A legacy file
needs a reviewed values-only XLSX containing the four header rows and A:AD,
with text identifiers and exact numeric cells. Cross-check the conversion
against its source. The source's extra columns, formulas and placeholder
structures can make a direct Save As unsuitable for import.

Automated tests exercise actual XLSX archives, including deflated edited
workbooks, malformed headers, duplicate and ambiguous matches, precision and
type errors, tectonic row groups, stale revisions, partial completion and
restart recovery. The tests preserve a linked original photo and measurement,
J5 and historical Q/RMR89/GSI/JCond76 snapshots. Direct XLSB import, a native
Excel resave of the owner workbook and on-device Files-provider acceptance
remain unverified.

Stage 4c verification on 2026-11-11

- SwiftPM ran 89 targeted tests across regulatory export, Exchange import and
  export, Files coordination, preview coordination and the ledger. All passed.
- Xcode 26.6 `build-for-testing` succeeded for the generic iOS Simulator
  destination with signing disabled. The app, unit test and UI test targets compiled.
- The full regression suite and physical-device walkthrough were outside this run.
