# FieldForge Exchange v1 — B2a export contract

Status: **export and B2b read-only preparation**; applying proposals remains B2c. See [B2b implementation and write-stage design](excel-exchange-b2b.md). Workbook filename: `FieldForge Exchange.xlsx`; discriminator:
`FieldForge-Exchange/1`; mapping schema: **8**. Parent: [#68](https://github.com/tinuvael/FieldForge/issues/68).
B2b validates and previews proposals without writes; B2c import is not implemented. This contract does not authorize replacement of evidence,
and does not close #68 or backup/restore #23.

## Audit and implementation boundary

- `MappingJournal.validate()` and `validateRevisions(context:)` are authoritative. Projects,
  horizons and excavations have stable UUIDs; excavation/horizon membership is many-to-many
  within one project. Observations retain immutable parent IDs, creation/update timestamps
  and measurement membership. An original is version 1, whose revision identity is its own
  observation UUID. Corrections append `MappingObservationRevision` records (version >= 2).
  The first correction's `previousRevisionID` is null; later corrections link to the previous
  correction UUID. `correctedAt` is separate from field `observedAt`.
- J1–J5 are explicit, versioned `InterpretedJointSet` interpretations, with their own UUID,
  author/time/method, manual source spelling, north/conventional-side metadata, linked
  original measurement UUIDs and spacing provenance. They are not five automatic sensor groups.
  Measurements retain acquisition source, diagnostics, algorithm, original manual strings,
  quality and undefined directions. Tectonic orientations may be incomplete.
- Geological context includes picket conventions, interval bounds, observation position,
  lithology/project lithology catalogues, tectonics and notes. Q, RMR89 and GSI keep their
  existing method/version, inputs, missing state and saved assessment representation. Legacy
  RMR input-only records remain input-only. This change introduces no engineering formula,
  rating table, mechanical interpretation or numerical transformation.
- Coordinates retain optional X/Y/Z, CRS, axes, XY units, source and provenance, plan UUID,
  frozen horizon Z source/datum, or complete DXF-derived Z evidence (method, plan/hash/version,
  selected XY, units, segment/policy and optional additional wall). Schema 8 has no separate
  per-X/per-Y provenance or additional unstored CRS alignment/time accuracy metadata: do not
  invent it. Schema-8 `coordinates.source/provenance` describe XY together; Z has explicit source.
- Existing `MappingCSVExport` supplies normalized relational projections and the exact same
  project, optional horizon/excavation and inclusive local-calendar field-date selection.
  Existing Russian report sheets are presentation projections; their rounded display and
  absence of complete correction history make them unsuitable as an exchange base.
- Reuse `MappingXLSXExport`'s common OOXML rendering, text escaping, column addressing,
  style/filters/frozen-header infrastructure and `XLSXArchive`'s streaming ZIP32 writer.
  Report entry points retain their previous sheet order, styles, numeric/date rules and CSV
  serialization. Exchange adds a text-only rendering mode, not another XLSX dependency/writer.
- `MappingStorageOwner.exchangeSnapshot()` reserves the existing non-reentrant FIFO to select
  one immutable `MappingCommittedSnapshot` after earlier admitted writes. Projection, graph
  validation and ZIP creation then run off MainActor without holding the queue. Later commits
  cannot change the retained generation. Retired/suspended/unopened owners reject admission.
  Neither capture drafts nor files read directly from disk are used. The on-screen count is
  refreshed to the admitted generation; the selected filters are retained through sharing.
- B1a/B1b ([#69](https://github.com/tinuvael/FieldForge/pull/69),
  [#70](https://github.com/tinuvael/FieldForge/pull/70), [format 1](backup-format-v1.md))
  protect the entire durable dataset, exact independent journal and original photo/DXF bytes.
  Restore gates publication on application-model readiness and retires old owners. Exchange
  shares the same owner admission boundary but neither invokes restore nor substitutes for it.
  It does not alter either journal's schema, migrations, backups or write semantics.

## Desktop workflow

1. Save a complete verified backup ZIP separately.
2. Open «Картирование → Журнал → Выгрузка», select project/period and optional scope,
   then «Excel Exchange · обмен» → «Экспортировать Excel Exchange» → «Сохранить в Файлы».
3. Open the workbook in desktop Excel. Read «Формат» and «Колонки». All sheets are visible,
   have frozen headers and filters. Keep the stable English column keys. Copy the workbook
   for each colleague; retain its `workbook_id` and all base metadata. File renaming is harmless.
4. Prepare proposed edits in the current `points`, `joint_sets`, `tectonic_structures` and
   `assessments` rows. Keep exact-value cells formatted as **Text**; do not convert them to
   dates/numbers or paste formulas. Preserve the complete row when sorting.
5. Open «Картирование → Журнал → Проверка Excel» to validate the workbook and inspect
   the read-only B2b preview. There is no Apply action; desktop changes remain proposals.

A workbook is scoped to one project and the selected effective observations. All horizons,
excavations, membership links, project catalogue and plan metadata of that project are
included, even when no point matches. Original/history/evidence/photo metadata belong to
selected points only, including historical versions outside the field-date filter. Unassigned
mapping measurements, other projects, current UI selection, the independent measurement
journal, binary attachments, operation manifests and recovery sidecars are outside scope.

## Worksheet structure

The header row is normative; exact v1 columns are listed in the appendix. No formulas,
macros, hidden rows/sheets, numeric cells or Excel serial dates are generated.

| Sheet | Role and key | Future editing class |
| --- | --- | --- |
| Формат | Format/schema/workbook UUID, UTC and exact export time, selection, fingerprint version, Russian instructions | Immutable |
| Колонки | Russian field guide, units and proposal policy | Informational |
| projects | `project_id`, name and complete optional `lithologies_json` | Context only |
| horizons | `horizon_id → project_id`, optional elevation in m, datum | Context only |
| excavations | `excavation_id → project_id`, name | Context only |
| excavation_horizons | Composite `(excavation_id, horizon_id)` | Context only |
| points | One current effective row per `point_id`; stable parents, base IDs/version/hash, location/time/geology and proposal fields | Controlled correction or new point |
| measurements | `measurement_id → point_id`, exact original acquisition/orientation/manual/sensor data | Immutable evidence |
| joint_sets | `joint_set_id → point_id`, unique J1–J5, own revision, representative, spacing/provenance | Proposed interpretation correction/new interpretation |
| interpretation_evidence | `(joint_set_id, joint_set_revision, point_id, measurement_id)` | Immutable links in v1 |
| tectonic_structures | `structure_id → point_id`, incomplete orientation, type/thickness/location/description | Proposed correction/new description |
| assessments | `(point_id, kind)`; Q, RMR89 or GSI input/method/time/missing/results | Inputs may be proposed; derived fields immutable |
| photo_point_contexts | Frozen historic point context by `revision_id`; never a second effective observation or inferred photo location | Immutable |
| photos | `photo_id → point_id`, frozen context/version/location basis, source/time/current metadata | Context only |
| photo_attachments | `attachment_id`, expected hash/size/format and not-checked status | Context only |
| source_records | Full typed schema-8 records and history in hashed/chunked canonical JSON | Immutable exchange base |

`plans` are represented in full in `source_records` (no binary DXF or editable plan sheet).
UUID relationships, not a filename, picket, display name, sheet position or row number,
define every identity. Child rows attach to the owning point's exported effective version;
the point's base fingerprint covers that version and its evidence/context.

### Full source record representation

Columns: `kind, record_id, point_id, version, chunk_index, chunk_count, sha256, json_chunk`.
Kinds: `project`, `horizon`, `excavation`, `plan`, `original`, `revision`, `measurement`,
`photo`, `photo_attachment`, `photo_revision`. `point_id` is populated for observations,
revisions, measurements and photos; other relationships remain in their full typed JSON.
`version` is the observation/photo correction version for revision kinds, otherwise 1
(record container version; plan/geological versions remain inside JSON).

Each source record is the entire model's synthesized schema-8 Codable JSON; optional nil
keys are omitted as in current storage. `excavation.horizonIDs` alone is normalized to a
lexicographically sorted UUID array (the model is a Set). JSON keys are sorted, slashes are
unescaped; dates are finite binary64 seconds since 2001-01-01T00:00:00Z, serialized by
Foundation JSONEncoder's round-trip numeric spelling. JSON numbers are **inside text cells**,
never Excel numbers. Reconstruct by concatenating `json_chunk` in integer `chunk_index`
order (zero-based). Check count, unique contiguous indices and repeated lowercase SHA-256
of the complete reconstructed UTF-8 bytes. Chunks are at most 16,000 UTF-16 units, split only
between Unicode scalars. JSON is context/base evidence, never an editable replacement object.
It preserves every stored field in the selected record graph, including optional geology,
spacing/conventional-side provenance, rock descriptions, saved rating data, full sensor
samples, photo corrections, plan confirmations/management lineage and unknown metadata.

Normalized sheets are useful desktop projections. When they omit a source detail or show
a derived convenience value (ISO date, normalized orientation, current assessment evaluation),
full source JSON retains the original. No field missing from the projection is silently
lost. JSON does not contain original attachment bytes or certify their presence.

### Identity, base and deterministic conflict metadata

Existing points export `record_action=existing`, empty `client_record_id`, `point_id` and
`original_id` equal to the stable original observation UUID, `revision_id` equal to the
latest correction UUID or the point UUID for version 1, and the current integer `version`.
`base_fingerprint` is lowercase SHA-256, algorithm `FieldForge-Exchange-Base/1`.

Its exact UTF-8 preimage is `MappingExchangeExport.json(Base(...))` with keys:
`format, original, revisions, measurements, project, horizon, excavation, plans`.
`format` is the fingerprint algorithm string; original is the immutable observation;
revisions are the complete authoritative append-only chain in version order; measurements
are complete originals in the observation's ordered `measurementIDs`; project/horizon/
excavation are current full parents, with excavation membership sorted; plans are **all
plans in that project**, ordered lexicographically by UUID. Key ordering and serialization
are as above. No workbook ID, export time, filter, current selection, row position or other
project enters the hash. Row/record collection reorderings do not affect it; meaningful
ordered evidence arrays do. Parent/plan edits conservatively invalidate affected bases even
if an engineer only edits a note. SHA-256 is a comparison token, not authentication.

Future B2b must verify the base source records against current immutable evidence and the
fingerprint recomputed from the current committed graph, not trust a spreadsheet hash alone.
Historical bases must remain unchanged through desktop editing. If cross-runtime canonical
JSON spelling changes, retain a v1 verifier or version the algorithm; never silently switch
normalization. Raw source JSON bytes and their hashes travel in the workbook for diagnostics.

New points: append one row with `record_action=new`, a globally unique UUID in
`client_record_id`, and **empty** `point_id, original_id, revision_id, version, base_fingerprint`.
Supply explicit existing parent UUIDs and valid observation inputs. Children use that
`client_record_id` in `point_id`, and unique proposed child UUIDs in their ID columns.
No new original sensor/manual measurement rows are supported by this v1 proposal profile.
The new point's creation/update/version identity and import provenance are assigned only at
admission. B2b must use a durable `(workbook_id, client_record_id)` admission mapping to the
collision-checked final UUID, and retain the admitted proposal digest; reopening/reimporting
must consult it. Its persistence design is a B2b prerequisite, not implemented here. Randomly
assigning another UUID on each import, or treating an unrelated UUID collision as a replay,
is forbidden. No deduplication by picket/name or content-only fuzzy matching is permitted.

### Editable and protected fields

All edits remain proposals until B2b validates them against the same domain rules used by
controlled corrections. Worksheet locking is not a security boundary; B2a does not add
password protection or imply that editable cells grant overwrite permission.

| Class | Fields / behavior |
| --- | --- |
| Proposed correction, existing or new | Point picket/numeric chainage and declared origin/direction; field time/zone/offset; notes; interval start/end/position; manual X/Y/Z with explicit CRS/axes/units/provenance; rock selection/description; joint representative manual strings/north/conventional side, author, spacing/persistence/aperture/roughness/infill/notes; tectonic descriptive inputs; existing method-qualified rating input JSON/text |
| Required on a correction | `correction_reason`; optional `correction_author`. Correction timestamp is assigned at acceptance, never taken from the spreadsheet's old base timestamp |
| New observations only | `record_action=new`, `client_record_id`, valid project/horizon/excavation UUIDs, initial interpretation IDs. Parent reassignment of an existing point is forbidden |
| Immutable | Existing IDs/base version/fingerprint; all source_records; original measurements/manual strings/diagnostics; measurement membership; existing geological identity and baseline revision/method/time; interpretation evidence links; creation/update/correction timestamps; base project/plan/catalogue/photo context |
| Calculated or unsupported | Stored ratings/evaluations/classes/missing/status fields, normalized dip/direction helpers when original manual strings are authoritative; project/horizon/excavation/catalogue editing; new plans, transformations, sensor records, photo metadata/binary changes, deletion and reassignment |

For `assessments`, saved `input_json` holds the complete Q/RMR inputs; GSI keeps its saved
assessment in `input_json`. Existing method/version and derived results are protected.
Where input text is repeated in convenience columns (`rqd_text`, RMR input columns, joint
representative JSON/text), B2b must require consistency or report an ambiguous proposal;
never choose whichever duplicate field was parsed last. GSI method/assessment-time/result
must remain base metadata; supported selection/range edits require existing GSI validation.
B2b must regenerate derived assessments through the existing verified domain services only
when accepting changed inputs. Deleting child rows does not imply removal; v1 does not
support spreadsheet deletion. New joint interpretations have no measurement evidence unless
explicitly supported and previewed in a later contract. Existing evidence links are retained.

For existing coordinate corrections, v1 admits only explicit manual-source proposals;
plan-derived/manual-in-plan and calculated Z source changes require a future supported
profile, never a fabricated surveyed/plan provenance. Preserve their existing JSON/values
when making unrelated edits. Never infer coordinates from photo EXIF or desktop row order.
Picket text/numeric values must agree under the stored convention; changing a convention on
an existing point is unsupported. A future importer must reject inconsistent duplicate inputs.

## Precision, nulls, time and conventions

- **All non-null cells use inline strings and text number format**, including UUIDs, integers,
  exact decimal Double strings, method versions and timestamps. Column defaults are Text
  for newly entered rows. No leading CSV protection apostrophe is added or removed.
- Decimal values use locale-independent `String(Double)` round-trip spelling, including
  exponent notation when appropriate; original manual input strings retain their decimal
  comma/leading zeros exactly. Excel's 15-digit number limit never touches authoritative
  exported decimals. Numeric formatting/paste by a desktop editor can still destroy this
  guarantee; B2b must detect ambiguous numeric/date cells and reject them.
- Empty cells mean missing **nullable** values, never 0. Required textual properties may be
  the empty string. `has_coordinates` / `has_geology` and full source records distinguish
  absent objects from present partial objects and retain nil versus empty optional text.
  An unchanged blank must preserve its baseline representation. Clearing a nullable input
  means nil; clearing a required text means empty string where domain validation allows it.
- `*_utc` ISO-8601 values are display helpers at millisecond precision. Their text
  `*_reference_seconds` companions and JSON dates retain the exact stored Date Double.
  `observed_zone` and historic `observed_offset_seconds` are independent preserved values.
  If a proposal changes time, exact seconds and ISO helper must agree to the helper's
  precision; zone/offset must be explicit and consistent. Do not invent original clock
  accuracy/precision, timezone for measurement timestamps, or capture times not stored.
  Sub-millisecond Date precision is storage precision, not a physical accuracy claim.
- Chainage/intervals, Z, spacing, persistence and thickness are metres; aperture is mm.
  XY units are `m`, `mm` or `drawing` under the saved CRS/axes. No unit/CRS or magnetic/
  true/grid/unknown north conversions occur. Directions are downhill, conventional vertical
  dip side or undefined as recorded. Manual raw strings and source north are retained.
- A single projected text cell longer than Excel's 32,767 UTF-16 units fails export with a
  Russian error; no truncation. Full source JSON alone can span many chunks. XLSX sheet
  limits (16,384 columns / 1,048,576 rows including header) and ZIP32 (<4 GiB, bounded part
  counts) also fail explicitly. The disposable export directory is cleaned on failure or
  cancellation. Source files are never opened or modified.

## B2b required import outcome rules (not implemented)

Read and validate everything in isolation; show counts and details of new, unchanged,
corrections, duplicates, conflicts, invalid and unsupported rows before confirmation.

| Input | Required future outcome |
| --- | --- |
| Unchanged current record | No write, no new revision |
| Changed existing record with current base | Preview controlled correction; preserve original and append history only after confirmation |
| Missing/changed base, stale parent/context or concurrent revision | Conflict; reject batch; explicit re-export/rebase required, no last-write-wins |
| New valid client record | Preview, reserve collision-safe identity and persist admission provenance atomically with accepted graph |
| Exact duplicated row/chunk/link | Report duplicate and collapse only if every logical field is identical |
| Same logical identity with divergent rows/chunks | Invalid/ambiguous; reject batch regardless of worksheet order |
| Reordered rows/sheets | Identical outcome, except meaningful array order explicitly retained in JSON |
| Same workbook/proposal reimported | Zero new points/revisions via durable admission/proposal mapping; report replay |
| New proposal under an already admitted client token | Conflict, never another new point |
| Immutable/unsupported edits, formulas, invalid parents/source metadata | Explain row/field and reject; do not ignore silently |
| Missing child/base rows or unsupported version/schema | Reject; omission never means deletion |

Re-check current revision/context/fingerprints **inside `MappingStorageOwner`'s accepted
transaction** after preview, and run authoritative graph/revision validation. All admitted
writes, including durable replay/provenance state, must form one recoverable confirmed batch;
invalid input and failure must cause no partial mutation. Do not mutate originals, photo/DXF
files or the independent journal. The durable admission/proposal ledger and its atomicity
with schema-8 storage need a reviewed B2b design before importer implementation; no
speculative importer models or storage have been added in B2a.

## XLSX security and compatibility

Output is OOXML Transitional using inline strings (existing writer), UTF-8 ZIP entry names,
CRC-32 and local/central directory descriptors. User `=`, `+`, `-`, `@`, whitespace/control
prefixes, apostrophes and hyperlinks remain literal text; there are no `<f>` elements,
hyperlink objects, VBA, external relationships or generated formula calculations. XML
metacharacters are escaped and SpreadsheetML `_xHHHH_`/control escapes preserve source
strings, including carriage returns and escape-like user text. Unicode and Russian text
remain unchanged. Normal Excel text cells may display formula-looking content without
executing it. Copying values into other formats is outside the XLSX protection boundary.

B2b must independently bound compressed/uncompressed sizes, compression ratio, entry count,
XML complexity/text lengths and cells; reject duplicate/unsafe ZIP names, traversal/symlinks,
DTD/entities, macros, external relationships/connections, unsupported formula cells (including
cached results), unexpected parts and ambiguous dates/numeric coercion. Never fetch links or
evaluate formulas. Permit only an explicitly supported set of normal Excel save rewrites
(e.g. shared strings and ZIP compression) with equivalent semantic validation. The existing
backup reader only handles the backup's STORE profile and is not a desktop XLSX importer.
Workbook UUIDs/hashes are not signatures; a workbook is untrusted input even if exported by
FieldForge. Binary photo and DXF originals require the separate verified backup/export flow.

## Verification and remaining qualification

The focused B2a suite checks two deterministic isolated projects, parent UUIDs, J1–J5 with
multiple original measurements, originals/effective corrections, nulls, horizon/manual Z,
CRS/axes/source, exact decimal/timestamp representation, fingerprint sensitivity/order,
formula-like and Russian/Unicode/control text, chunked source reconstruction, FIFO admission,
refusal/cleanup and report compatibility. It independently reads ZIP directories/XML and
compares every actual emitted cell. A deterministic synthetic sample is generated from that
fixture (no user/device data). The existing XLSX tests are included in the same focused run
because the common writer is reused. One incremental generic Simulator Debug build verifies
SwiftUI integration; it does not qualify Excel application behavior or Files providers.
Full regression, physical-device operations, benchmarks and Excel/LibreOffice UI testing
are deliberately outside this PR. Final focused run: **18 tests executed, 17 passed, one pre-existing opt-in reporting fixture skipped,
zero failures** (six B2a tests and the existing XLSX compatibility suite). Final generic iOS
Simulator Debug build succeeded for arm64/x86_64, signing disabled and Complete Strict
Concurrency Checking. Workbook ZIP/XML/source hashes/base fingerprint were also independently
checked with Python, then loaded with openpyxl 3.1.5. No source concurrency warnings. Existing
CoreSimulator runtime/service discovery errors and the AppIntents extraction notice remain;
no runtime launch/provider qualification is claimed. Logs: `/tmp/fieldforge-b2a-tests-final.log`,
`/tmp/fieldforge-b2a-simulator-final.log`.

Initial verification attempts found compiler issues in new test scaffolding and an incorrect
historic Almaty offset expectation (+06:00 for the 2023 fixture, preserved rather than replaced
with today's +05:00); these were corrected. A subsequent workbook inspection identified narrow,
unwrapped guide columns. The guide formatting was fixed and the focused suite plus incremental
build were repeated once for that concrete change; no full regression or physical device work.

## Appendix: v1 exact column inventory

### Формат

`key, value`

### Колонки

`sheet, columns, description_ru, policy`

### projects

`project_id, name, lithologies_json`

### horizons

`horizon_id, project_id, name, elevation_m, elevation_datum`

### excavations

`excavation_id, project_id, name`

### excavation_horizons

`excavation_id, horizon_id`

### points

`point_id, revision_id, version, project_id, horizon_id, excavation_id, picket, chainage_m, chainage_origin_direction, observed_at_utc, observed_zone, observed_offset_seconds, created_at_utc, corrected_at_utc, interval_start_text, interval_start_m, interval_end_text, interval_end_m, position, x, y, z_m, xy_units, crs, axes, coordinate_source, coordinate_provenance, z_origin, z_horizon_id, z_horizon_elevation_m, z_datum, plan_id, notes, z_plan_geometry_json, observed_at_reference_seconds, created_at_reference_seconds, corrected_at_reference_seconds, record_action, client_record_id, original_id, base_fingerprint, picket_convention_json, rock_json, measurement_ids_json, updated_at_reference_seconds, has_coordinates, has_geology, correction_reason, correction_author`

### photo_point_contexts

`point_id, revision_id, version, project_id, horizon_id, excavation_id, picket, chainage_m, chainage_origin_direction, observed_at_utc, observed_zone, observed_offset_seconds, created_at_utc, corrected_at_utc, interval_start_text, interval_start_m, interval_end_text, interval_end_m, position, x, y, z_m, xy_units, crs, axes, coordinate_source, coordinate_provenance, z_origin, z_horizon_id, z_horizon_elevation_m, z_datum, plan_id, notes, z_plan_geometry_json, observed_at_reference_seconds, created_at_reference_seconds, corrected_at_reference_seconds`

### measurements

`measurement_id, point_id, timestamp_utc, dip_direction_deg, dip_angle_deg, north, direction_meaning, source, quality, status, plane, algorithm_version, original_direction_text, original_dip_text, notes, sensor_sample_json, orientation_json, timestamp_reference_seconds`

### joint_sets

`joint_set_id, point_id, revision, identifier, interpreted_at_utc, author, method, dip_direction_deg, dip_angle_deg, north, direction_meaning, original_direction_text, original_dip_text, spacing_m, persistence_m, aperture_mm, roughness, infill, notes, interpreted_at_reference_seconds, representative_json, spacing_provenance_json`

### interpretation_evidence

`joint_set_id, joint_set_revision, point_id, measurement_id, role`

### tectonic_structures

`structure_id, point_id, type, dip_direction_deg, dip_angle_deg, north, original_direction_text, original_dip_text, conventional_dip_side, thickness_m, picket_text, chainage_m, position, description`

### assessments

`point_id, kind, method, revision, assessed_at_utc, stored_q, stored_q_class, rqd_text, jn_text, jr_text, ja_text, jw_text, srf_text, input_json, stored_evaluation_json, missing_json, rmr_strength_test, rmr_strength_mpa_text, rmr_strength_evidence, rmr_rqd_evidence, rmr_spacing_m_text, rmr_persistence_m_text, rmr_aperture_mm_text, rmr_roughness, rmr_infill, rmr_weathering, rmr_groundwater, rmr_inflow_l_min_per_10m_text, rmr_water_pressure_ratio_text, rmr_application, rmr_orientation_description, rmr_source, rmr_assessor, rmr_missing_reason, rmr_status, stored_rmr_basic, stored_rmr_class, stored_rmr_calculation_json, assessed_at_reference_seconds`

### photos

`photo_id, point_id, project_id, horizon_id, excavation_id, context_revision_id, context_point_version, capture_location_basis, name, number, description, category, metadata_revision_id, metadata_version, metadata_corrected_at_utc, source, captured_at_utc, capture_time_text, capture_time_provenance, imported_at_utc, attachment_id, original_integrity, metadata_corrected_at_reference_seconds, captured_at_reference_seconds, imported_at_reference_seconds`

### photo_attachments

`attachment_id, original_filename, sha256_expected, byte_count_expected, format, mime_type, pixel_width, pixel_height, orientation, representation, original_integrity`

### source_records

`kind, record_id, point_id, version, chunk_index, chunk_count, sha256, json_chunk`

Synthetic sample: [FieldForge Exchange.xlsx](samples/FieldForge%20Exchange.xlsx).
Generated by `MappingExchangeExportTests` from fixed UUIDs/timestamps and synthetic inputs.
The fixture has two isolated projects; this workbook exports project A only, as the UI does.
To regenerate, set `FIELD_FORGE_EXCHANGE_SAMPLE=/tmp/FieldForge\ Exchange.xlsx` when running the focused suite.
Its point base fingerprint is `f5ddf972298512ae5ee43f2dc8eae0a3a5c8398cfad079926118daf1196ac3b0`; ZIP CRCs, relationships, all-source hashes
and this fingerprint were independently checked with Python stdlib, and the workbook loaded with openpyxl 3.1.5.
