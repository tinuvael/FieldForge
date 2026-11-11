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
cropped to A:AD with the four original header rows. Reconcile numeric ROCK
codes against the project catalogue. The source workbook's extra columns,
formulas and placeholders require review before conversion.

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
