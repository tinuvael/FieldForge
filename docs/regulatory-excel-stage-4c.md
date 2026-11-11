# Regulatory Excel Data A:AD operational workflow

The regulatory XLSX is FieldForge's primary workbook for exchanging and editing
the mapping database. FieldForge keeps the committed observations, revisions,
original evidence, attachments and import receipts in the offline journal.

1. In **Журнал → Выгрузка**, choose **Геотехническое картирование — регламент**.
   The default selection includes all dates in the selected project. Horizon,
   excavation and field-date filters remain available.
2. Edit or add rows on `Data`. Keep the four header rows, columns A:AD and the
   hidden `_FieldForge` worksheet. Repeat the same observation-level values on
   each tectonic row.
3. Open **Журнал → Импорт Excel → Регламент · Data A:AD**. Choose the XLSX. For
   new rows, confirm the project, horizon, field date and time, picket
   convention, and chainage origin and direction. An exact ID can select a
   unique existing excavation on that horizon. Choose the excavation when ID
   is missing or ambiguous. Missing PK requires an explicit picket.
4. Resolve uncertain matches, grouping and revisions. Open each proposal to see
   its observation, Excel row numbers, current and proposed values, and any
   changed calculated Q or RMR89 totals. Select observations and confirm.
5. Review the import report. New observations appear in the journal and on the
   associated DXF plan when their XY frame and coordinates are available.
   Export the consolidated observations for the next edit cycle.

## Workbook identity and legacy compatibility

`FieldForge-Geotechnical.xlsx` retains the established `Data!A:AD` headers,
column order, values, styles, merges, filter and print settings. Tests compare the
complete Data worksheet XML with and without the hidden sheet. The hidden
`_FieldForge` sheet carries the workbook UUID, original row ranges, observation
UUIDs and owners, revision IDs, and fingerprints. A single XLSX carries the
entire exchange workflow. Choose **Совместимость · только лист Data** for
consumers that require a single-sheet workbook.

The reader checks hidden bindings against archived observation snapshots in the
journal. You can insert rows anywhere, sort the entire A:AD range below row 4,
or reorder complete rows. A unique, exact match to the archived Data values
reports an unchanged observation, even when its row numbers or tectonic-row
order changed. The current journal version is retained. Changed groups require
an explicit observation match. Original row positions can offer a candidate
when a group disappears from its former A/B context. They never establish a
write target.

When an original group is missing and an unmatched group appears, explicitly
choose an existing observation or confirm creation. This also covers a moved
row with a changed picket. In a legacy workbook, A/B and chainage shortlist
candidates. Review the project, horizon, excavation, field date and UUID before
matching. Coordinates never establish identity. Removing a worksheet row does
not delete a saved observation or fault.

Rows with the same A/B and identical observation-level cells may describe
several faults. Confirm whether additional rows belong to that observation.
Unique unchanged S:U values retain their fault UUIDs regardless of row order.
For a changed fault row, choose the saved fault explicitly. Unmatched rows
can be added after the saved faults are accounted for. The preview shows the
actual Excel row alongside the saved and proposed values. Duplicate rows and
multiple groups targeting one observation require reconciliation.

## Excel conversion and import limits

The reader resolves the visible sheet named `Data` through the workbook
relationships. It reads actual cell addresses and ignores Excel's cached
worksheet dimension. It accepts additional visible and hidden worksheets.
Only `Data` and the optional hidden `_FieldForge` sheet are read. Shared
strings are loaded if a required sheet contains shared-string cells.
Styles are loaded when a numeric Data value needs format validation.
Core properties provide the workbook identifier when present.

Calculation chains, themes, secondary sheets and their relationships, and
recognized drawing, control-property and printer assets are skipped.
Relationships of the imported worksheets may reference internal printer
settings. External workbook links, macros and connections are rejected.
Formula cells and their cached results are flagged as unsupported inputs.

The ZIP32 reader validates entry paths, local and central headers, payload
extents, sizes and declared ratios even for skipped entries. It accepts
STORE and raw DEFLATE, with bounded decoding and CRC-32 verification for
parts it reads. XML and CRC validation cover the consumed parts.
Regulatory limits are 32 MiB compressed, 256 MiB declared uncompressed,
128 MiB cumulatively decoded, and 1,000:1 per entry. Supporting parts have
a 32 MiB buffered limit. The required `Data` sheet uses incremental
STORE/DEFLATE decoding with 64 KiB chunks and SAX parsing, with a separate
112 MiB output ceiling. The streaming path checks the exact length, end
of DEFLATE stream and CRC before publishing a preview. It rejects DTDs and
entity declarations across chunk boundaries and checks cancellation while
reading and parsing. Data is limited to 2 million scanned cells, 650,000
retained cell values or references, 6 million XML elements, and the
existing limits of 100,000 rows, depth 48 and 32,767 UTF-16 code units per
cell text. The 100 MB expanded worksheet never becomes a single buffer.

### Production workbook diagnosis

The Excel conversion supplied for this bug has 12,859,434 file bytes and
136,085,253 declared uncompressed bytes. The original importer stopped on
`xl/worksheets/sheet1.xml` because its 100,155,069 bytes exceeded the
32 MiB per-entry limit. The preceding entries brought the running total to
100,162,808 bytes at that point, within the old 128 MiB cumulative limit.
The full archive would have exceeded that cumulative limit by 1,867,525
bytes. Its highest compression ratio is 11.90:1, well within the 1,000:1 limit.
The 27,201,205-byte calculation chain also contributed to the old total.

The workbook links `Data` to `sheet1.xml`. The worksheet declares
`A1:CP19999` and contains 19,998 row elements and 1,724,884 cell elements.
The populated mapping candidates are rows 5–15. Later template rows have
dash placeholders in the mapping fields and calculated or auxiliary
content elsewhere. The `kart` sheet is a formula projection in a different
column order. Its NAME and PK columns reference Data A and B.

The reader recognizes the extended layout using the four A:AD header rows
and the additional headers at AE4, AH4, AI3, AJ3, BI1 and CP3. It reports
supplementary columns and opens batch reconciliation for these source
records. The ordinary four-header A:AD contract uses its existing
reconciliation and approval workflow.

| Source cells / labels | Verified structure and treatment |
| --- | --- |
| A3 «Место картирования», A4 `ID`, A5:A15 | The owner confirmed these are source observation IDs. The source ID is stored independently of the FieldForge observation UUID and any destination. |
| B3 «Пикетаж», B4 `PK`, B5:B15 | All 11 candidates contain `-`. Imported records may have an empty picket. A populated text picket is retained as supplied. |
| C3 «Координаты точек замеров», C4:E4 `X`, `Y`, `Z` | Six candidate triples use Excel text and five use numeric cells. Both preserve the source decimal spelling. Spatial comparisons use finite binary64 values, and Z remains absolute elevation in metres. |
| F4:N4, P4:R4, S4:AC4 | These source inputs are available in the source record detail. Their retention does not validate the source catalogue, rating method or azimuth north reference. |
| O3 «Расстояние между трещинами, м», O4 `SD` | Ten source rows have a spacing summary. It is stored as a source field. Original spacing per joint set remains unknown. |
| AD3:AD4 `GSI` and AE4:AH4 `Q'`, `Q`, `RMR89`, `RMR76` | Formula-derived GSI and the supplementary rating columns remain in the source workbook. Their caches do not supply assessment provenance. |
| AI3 «№ точки наблюдения» and AJ3 «Примечание» | AI is populated even on template rows. Its relationship to persistent identity is unverified. AJ contains dash placeholders for the 11 candidates. Both columns remain in the source. |
| AK4:BB4 | Auxiliary ratings, inputs and calculations remain in the source. `AT4 RMR76` includes a literal value among formulas, `AW4 благоприятность трещин` contains literal inputs with unconfirmed scoring provenance, and BB4 has no label. |
| BI1 «Ошибки в пополнении БД по картированию выработок» through CP | Worksheet validation formulas, booleans and cached errors remain in the source. Conditional formats are parsed as display markup. |

### Batch import and location resolution

Choose the project and a stable dataset name. Use the same project and
dataset for later editions of the source, even when the file name or row
order changes. The scoped key is project UUID, dataset name and exact
source ID. Confirm XY CRS, axes, units and vertical datum once. Explicitly
unknown metadata allows import and leaves frame-dependent rules inactive.
The workbook is read-only and its SHA-256 and source row are recorded with
each new version. Keep the original XLSX with the supplementary columns.

Resolution uses existing explicit source assignments first. For compatible
DXF revisions, confirm the plan's actual datum and its association with the
horizon and, where known, the excavation. Set two project-specific limits
in metres: maximum horizontal distance to a supported WCS segment and
maximum difference from the local segment elevation. Both limits require
explicit values. The reader verifies the managed DXF's hash, CRS, axes,
units and datum. It reuses the [existing WCS projection and elevation
index](p2-dxf.md) to compare the imported Z with the segment elevation at
the observation's XY. Inclined segments therefore use the local elevation.
Multiple eligible horizons leave the destination unresolved. A unique
horizon with competing excavation associations leaves excavation blank.
The import neither converts the coordinate frame nor alters XYZ.

When no verified DXF corresponds, a unique configured elevation range in
the confirmed datum can supply the horizon. An overlapping range leaves
the destination unresolved. The profile supplies no verified new horizon
identifier. A user can create a named horizon through the project editor
and assign a source group later. Coordinate proximity alone supplies no
excavation identity.

The preview shows new, matched, revised, conflicting and unresolved
records and the excluded source fields. Confirmation rechecks the XLSX
hash and the journal generation. The production batch uses one atomic
journal save. Duplicate source IDs, incompatible cells, stale previews
and conflicts block the batch before storage. Replayed evidence is
unchanged, edited evidence appends a version to the same UUID, and
resubmitting an older differing version reports a conflict. Changing
context from **Журнал → Наблюдения из Excel** also appends a version
without changing the UUID. Use the preview's horizon filter or selected rows for a bulk correction
before confirmation. In the journal, filter by dataset or horizon and
select a group to assign it together.

Schema 8 stores these source-backed observations in an optional field
of the same project journal. Existing schema-8 files and backups decode
with an empty source collection. New backups include the source records
and count them in the manifest. The source journal shows retained input
fields and assignment history. Promotion to field-capture observations,
linked photography, plan point rendering and export of source records
through the established A:AD assessment projection require further
integration. The current journal uses whole-state JSON validation and
atomic replacement. XLSX decoding is streamed and input limits remain
bounded. Reconciliation and commit hold a bounded in-memory batch and
journal snapshot, with phase-level progress and cancellation before
storage admission.

## Exact A:AD column policy

The [reference audit](regulatory-excel-audit.md#exact-aad-mapping) records the
four header rows, including the trailing space in S3. The row-4 keys and exact
source and import rules are below. `p` means effective observation, `q` is
the saved Barton Q input, and `r` is the saved RMR89 input.

Blank cells and the legacy dash retain existing values. In a new observation
they leave optional values missing. Text `#CLEAR` explicitly removes an
eligible optional value. Numeric zero remains a value. Exact numbers are
validated before proposal creation, and date, percentage and unsupported
numeric formats or cached formula results are rejected. A text ID or picket
must retain its text representation. When a resave appears to round a
high-precision value to Excel's 15 significant digits, keep the exact journal
value explicitly or restore the original cell.

| Column / key | FieldForge source, type and units | Import policy |
| --- | --- | --- |
| A `ID` | Excavation name through `p.excavationID`, text | Creation context. Resolve within the assigned project and horizon. Existing ownership is immutable through workbook revisions. |
| B `PK` | `p.displayPicket`, text in the declared picket convention | Parse and validate using the existing convention or the explicitly chosen creation convention. A changed picket may require manual identity matching. |
| C `X` | `p.coordinates?.x`, finite number in the declared XY frame | Editable. Retain the number without conversion. |
| D `Y` | `p.coordinates?.y`, finite number in the declared XY frame | Editable. Retain the number without conversion. |
| E `Z` | `p.coordinates?.z`, finite elevation in metres | Editable as an Excel-sourced manual elevation. A changed XY with DXF-derived Z requires an explicit Z or clear. |
| F `ROCK` | `p.rock?.code`, exact catalogue text | Editable. Preserve lexical zeroes. Legacy numeric cells require explicit mapping to a matching exact code in the project catalogue. The mapping applies to that number within the project. |
| G `A45` | Independent wall-alteration score, with equivalent RMR89 fallback | Editable independent category. Scores 6, 5, 3, 1 and 0. A clear requires the remaining projection to be blank. |
| H `JW` | `q.jw.value`, dimensionless NGI Q water coefficient | Editable if the value identifies a published category or fits the existing applicable category. RMR groundwater stays separate. |
| I `A1` | Independent strength band score, with field-grade fallback | Editable independent category. Scores 0, 1, 2, 4, 7, 12 and 15. A clear requires the remaining projection to be blank. |
| J `UCS` | `r.strengthMPa` for `r.strengthTest == .ucs`, positive MPa | Editable as UCS. An existing Is(50) or field-strength method requires reconciliation in the journal. |
| K `RQD` | `SpacingRQD(q:rmr:)` from original inputs, 0–100% | Editable where one source is represented. A new value is an external-report Q input when there is no existing RMR RQD. Two saved sources require separate reconciliation. No use of Q's numerical floor. |
| L `JN` | `q.jn.value`, dimensionless NGI coefficient | Editable with unique published or already selected applicable category. |
| M `JR` | `q.jr.value`, dimensionless NGI coefficient | Editable with unique published or already selected applicable category. Equal scores across categories require clarification. |
| N `JA` | `q.ja.value`, dimensionless NGI coefficient | Editable with unique published or already selected applicable category. Saved wall-contact constraints apply. |
| O `SD` | Mean of positive saved J1–J4 spacings, metres | Derived and read-only. Individual spacings cannot be recovered from the mean. |
| P `A43` | RMR89 aperture category, dimensionless score 6, 5, 4, 1 or 0 | Editable category. Keep the existing aperture measurement in mm and validate it against the choice when present. |
| Q `JCON76` | `r.jcond76?.rating`, historical score 25, 20, 12, 6 or 0 | Editable historical category using the existing edition and scoring table. Independent of the RMR89 total. |
| R `A42` | RMR89 persistence category, dimensionless score 6, 4, 2, 1 or 0 | Editable category. Keep the existing persistence measurement in metres and validate it against the choice when present. |
| S `F_DIP` | Tectonic dip of this row, degrees 0–90 | Editable with the saved or explicitly supplied orientation convention. Partial tectonic orientation can remain partial. |
| T `F_AZI` | Tectonic dip direction of this row, degrees 0–360 | Editable. New orientation uses the declared north reference, which may be unknown. |
| U `F_THI` | Tectonic thickness of this row, nonnegative metres | Editable. Explicit clear retains the tectonic record and removes thickness. |
| V `J_DIP_1` | J1 representative dip, degrees 0–90 | Editable interpretation. Complete the angle pair where required. |
| W `J_AZI_1` | J1 representative dip direction, degrees 0–360 | Editable interpretation. Preserve saved north or declare it for a new interpretation. |
| X `J_DIP_2` | J2 representative dip, degrees 0–90 | Same policy as J1 dip. |
| Y `J_AZI_2` | J2 representative dip direction, degrees 0–360 | Same policy as J1 dip direction. |
| Z `J_DIP_3` | J3 representative dip, degrees 0–90 | Same policy as J1 dip. |
| AA `J_AZI_3` | J3 representative dip direction, degrees 0–360 | Same policy as J1 dip direction. |
| AB `J_DIP_4` | J4 representative dip, degrees 0–90 | Same policy as J1 dip. |
| AC `J_AZI_4` | J4 representative dip direction, degrees 0–360 | Same policy as J1 dip direction. |
| AD `GSI` | `p.ratings?.gsi?.finalValue`, saved dimensionless estimate | Derived and read-only. A bare estimate cannot recover the chart position, range, method or provenance. |

For unsupported SD and GSI edits, the preview identifies the affected cells and
allows explicitly proceeding with the other fields while keeping the journal's
derived values. Legacy source values remain in the original workbook. The
[regulatory category contract](enterprise-geotechnical.md#regulatory-field-categories-stage-3a)
documents the A1, A45, A42 and A43 tables.

The import uses the existing NGI Q and RMR89 evaluators. Missing inputs remain
missing. Data supplies no SRF, Jn location adjustment, orientation adjustment,
raw aperture or persistence measurements, GSI chart evidence, or independent
RMR76 total. It cannot infer them from the nearby regulatory fields. Historical
Q, RMR89, GSI, JCond76 and J5 snapshots, original measurements and photographs
remain in the journal. A changed interpretation keeps the links to its original
measurements and creates a versioned snapshot.

## Spatial data and revision conflicts

For new or unbound XY, select a DXF revision when the workbook coordinates are
known to be in that drawing frame. Confirm the selected plan and its units.
With complete XY, the saved horizon, excavation and plan relationships flow
through the existing point renderer. Values without a confirmed frame are
retained as unbound drawing values and the journal reports the missing frame.
Incomplete XY remains in the journal. The import performs no coordinate
transformation, north conversion, GPS inference or DXF geometry edit.

When the journal has changed since export, FieldForge compares the intended
Excel edits against the archived export baseline and shows the current values.
Approving Excel changes is tied to the current graph fingerprint. Journal
fields untouched in Excel are retained. Fault edits with concurrent local fault
changes require a fresh export. An apply-time conflict requires a fresh preview
and explicit resolution.

When you match a row, assign context or resolve a conflict, the refreshed preview
keeps approvals whose proposal, target and baseline still match. Changed,
conflicting and newly unmatched proposals need approval again. A stale preview
blocks confirmation until rechecked. Sorting or moving a row alone keeps its
approval if the proposed change is identical.

Confirmation re-reads the XLSX and checks its SHA-256. The storage owner
revalidates each target and commits the new observation or correction with its
receipt in the existing schema-8 journal. Pending intents retain the approved
assignment and can resume from the same source bytes. An exact replay reports
previously applied work. Re-export attaches UUIDs to newly created observations.
An edited legacy file without metadata requires renewed reconciliation.

## Reference and verification limits

The local `example(2).xlsb` matched SHA-256
`9991f51c1a170a224c219edc9eccfb1da3c54abd4f9f8095192e19bc90b66a97`.
Read-only extraction checked the A:AD headers and confirmed that populated A
and B cells are text and the 4,117 populated observation rows use numeric
ROCK cells. The file remains private. Import accepts XLSX. To use a legacy
XLSB, preserve the original and prepare a reviewed values-only XLSX copy
with the four original Data header rows and the supported A:AD fields.
Review extra columns, formulas and placeholders in the original before
preparing that copy. Reconcile numeric ROCK codes against the project
catalogue.

Automated tests use actual XLSX archives and cover insertion among existing
records, sorting across duplicate A/B anchors, reordering and adding fault
rows, and retaining unaffected approvals through matching, assignment, conflict
resolution and journal changes. The 100 + 20 / 5 revision scenario covers
exact Data XML, DXF point queries and missing XY, restart recovery, and
duplicate-free re-export and re-import. Native Excel
resaving of the reference, physical-device Files acceptance and full
regression remain outside this verification.

SwiftPM passed 128 focused tests across Excel import and export, file and
preview coordination, the import ledger, plan management and offline backup.
Xcode 26.6 `build-for-testing` compiled the app and test targets for the
generic iOS Simulator destination with signing disabled.

PR #81 finalization passed 94 targeted SwiftPM tests across regulatory and
Exchange XLSX, preview and file coordination, and the durable ledger. The
Simulator `build-for-testing` succeeded. The focused XLSX tests simulated
Excel insertion and sorting by relocating full worksheet rows and their cell
addresses while retaining the original hidden sheet.

The production XLSX fix passed 100 focused SwiftPM tests. One opt-in
independent workbook fixture was skipped. The cases include bounded synthetic
Office archives, invalid ZIP and XML, worksheet and package limits, preview
diagnostics, and duplicate-free application and replay of 20 new observations
and five revisions. Xcode 26.6 built the app for the generic iOS Simulator
destination. Full regression and physical-device import were outside this run.

The PR #82 streaming follow-up passed 80 focused SwiftPM tests with one
opt-in fixture skipped. The generic iOS Simulator build succeeded on
Xcode 26.6. Tests cover a valid worksheet above 32 MiB, CRC failure at the
end of a stream, a DTD token crossing a chunk boundary, size and cell
budgets, and refusal of a blocked preview before storage. Supported A:AD
imports still verify explicit DXF context, 20 creations, five revisions,
and duplicate-free replay through the durable ledger.

The initial streaming probe read 19,998 worksheet rows and found 11
candidates at rows 5–15. That version refused writes until a source-backed
observation type was available. Its macOS debug probe used about 63 MiB of
peak resident memory.


The automatic import probe reconciled the original production XLSX with
an empty in-memory project. It scanned 19,998 worksheet rows, parsed 11
source observations, proposed and accepted all 11, and reported zero
invalid rows, conflicts or initial matches. All 11 UUIDs and source IDs
were distinct. All destinations remained unresolved because the probe had
no verified project geometry or elevation ranges. Every picket remained
empty. Independent ZIP/XML extraction matched the exact decimal spelling
of all 11 saved Z cells. Replaying the input matched all 11 records as
unchanged and proposed zero new observations. The journal was serialized,
decoded and validated in memory. Peak resident memory in the macOS debug
probe was approximately 63.3 MiB.

131 focused SwiftPM tests passed and one opt-in fixture was skipped.
The tests cover two explicitly verified DXF excavations on
different horizons, inclined segment elevation, ambiguous ranges, unknown
frame metadata, duplicate input, dataset scope, stable reassignment,
revision replay and transaction rollback. Xcode 26.6 successfully built
the production preview and source journal for the generic iOS Simulator. Physical-device
verification and full regression were outside this run.
