# B2b — read-only Excel Exchange preparation

Parent: [#68](https://github.com/tinuvael/FieldForge/issues/68). Input remains
[FieldForge-Exchange/1](excel-exchange-v1.md), schema **8**. No migration, storage
ledger, import transaction, attachment operation or Apply action is implemented.

## User workflow and ownership

Open **Картирование → Журнал → Проверка Excel**, select an `.xlsx` through Files.
The preview states **«Предварительный просмотр. Данные ещё не импортированы»**.
It shows filename, format, project, export time, workbook UUID, selection and local
committed generation; seven counts navigate to reasons and field-level before/after
values. Nothing can be applied. Cancellation discards preparation; selecting another
file replaces the transient result. This is not backup/restore.

`MappingStorageOwner.exchangeSnapshot()` selects one immutable generation after
previously admitted work. `MappingCommittedSnapshot.generationID` is an ephemeral UUID,
not a schema field. Parsing, coordinated security-scoped file reading, decompression,
JSON reconstruction, domain validation and comparison run in a detached worker.
Freshness is checked after completion, when model publication changes, and once per
second through the owner while the preview is active. A changed generation or refused
owner marks the preview stale; regeneration is required. An editor never supplies a
draft or reads the database file. B2b only calls the owner's two read APIs; it cannot
invoke transaction/save/restore. New-point values are detached proposals, not journal
insertions. B2b creates no parsing directory, extracts no ZIP entries and opens no
photo/DXF/backup/independent-journal files.

## Preview operation lifecycle (2026-10-30)

`MappingExchangePreviewCoordinator` is a small screen-local MainActor object. A new
operation first revokes the previous operation UUID, then requests cancellation. Only
that UUID on an active screen can publish `preview`, `message`, `stale` or `busy`, including
from catch/defer paths. Admission is checked after snapshot admission, detached reading,
and freshness admission. User cancellation clears the active operation immediately;
leaving the screen revokes it without waiting for an uncooperative provider. Reopening
permits a new operation. No parser, classification, storage format or write API changes.

The original race was cancellation without publication ownership: an older cancelled
Task could resume after an await, write an error, clear a newer operation's busy flag in
its unconditional defer, or publish preview before the awaited freshness result. The
periodic reader could likewise apply an earlier response to a later preview or clear a
stale notification. A completed preview and its checked staleness now publish in one
state value; journal notifications received during checking are retained. Staleness only
advances to true for that publication. The existing one-second monitor is keyed by a
publication UUID rather than the journal generation (regenerations can share a generation),
and its result also checks the screen-appearance UUID after suspension. Cancelled monitors
and responses from a closed appearance cannot affect a reopened preview.

`MappingExchangeFileRead` retains the detached worker boundary and only reads bounded
bytes in the NSFileCoordinator accessor. The file handle and any acquired security scope
are balanced with defer, including failure/cancellation. They are released before archive
parsing/comparison or storage freshness awaits. Cancelling the worker invokes that read's
own `NSFileCoordinator.cancel()`; NSFileCoordinator.h permits this method from any thread
and documents that cancellation may race with an already-running accessor. The accessor
therefore checks task cancellation too. No access escapes its synchronous block, no file
is written or extracted, and no mapping/attachment/backup mutation is reachable.

Regression coverage uses controlled async continuations that deliberately ignore
cancellation, with explicit arrival/release/join barriers and no sleeps: A after B; A
while B remains busy; stale errors/defers; scoped cancellation; late snapshot/freshness;
journal changes during checking; no pre-freshness publication; leaving/reopening; late
periodic checks on the same generation or reopened appearance; monotonic stale state.
Files tests check acquired/not-acquired scope balance, success/failure/cancelled coordination,
production read/cancellation, unchanged bytes and directory inventory in isolated temporary
fixtures. No real Files-provider or physical-device qualification is claimed. Cancellation
cannot forcibly interrupt a synchronous file read already in progress; it must unwind its
accessor and defers, while UUID revocation already prevents any UI publication.

## Supported package profile and limits

The parser is intentionally narrower than general OOXML (ECMA-376 Transitional
SpreadsheetML/OPC; ZIP APPNOTE 6.3.10 §§4.3–4.4). Uses Foundation's SAX XML parser and
the operating system's zlib raw DEFLATE API; no external dependency or shell execution.

| Bound | Default |
| --- | ---: |
| Compressed/input file | 32 MiB |
| ZIP entries | 256 |
| Expanded individual part | 32 MiB |
| Expanded package total | 128 MiB |
| Individual expanded/compressed ratio | 1000 |
| XML element depth | 48 |
| XML elements per part | 2,000,000 |
| Rows across worksheets (including headers) | 100,000 |
| Cells across worksheets (including headers/blanks) | 500,000 |
| Cell/direct XML text / attribute UTF-16 units | 32,767 |
| Shared strings | 200,000 |
| Worksheet columns | 256 |
| Source chunk UTF-16 units | 16,000 |
| Chunks per source object | 10,000 (also bounded by package/cell totals) |
| JSON container depth | 48 |
| Individual JSON record / tokens | 32 MiB / 1,000,000 |

The initial file read is bounded independently of reported size. ZIP entries are
validated before decompression; actual DEFLATE output is capped by the declared size
plus one sentinel byte, with exact stream consumption and CRC verification. STORE and
raw DEFLATE, UTF-8 names, ZIP comments and optional data descriptors are supported.
Both local and central names/flags/sizes/CRC/extents must agree. Reject overlaps,
unaccounted payloads, unsafe/absolute/traversal/backslash/control/percent paths,
case-equivalent or duplicate names, symlinks, encryption, ZIP64 and alternative name
extra fields. No extraction means there is no destination path traversal surface.

Only the known workbook, relationships, worksheets, styles, shared strings, theme and
core/app metadata parts are accepted. All parts must be accounted for by internal
relationships and recognized content types. No external relationship is followed.
Macros, external links/connections, embedded objects, formulas including cached results,
worksheet hyperlinks/drawings/tables, unsupported extensions and arbitrary OOXML parts
are rejected. XML must be UTF-8, well formed, bounded, and free of DTD/entity declarations
and CDATA. External entity resolution is disabled. Metadata/style XML is checked too.

Resolve worksheets using workbook `r:id` and package relationships, independent of sheet
order. Header keys identify columns; rows/cells retain explicit addresses and are compared
using UUID/composite identities. Out-of-order rows and columns, normal style differences,
inline strings, shared strings and ordinary rich text runs are supported. ST_Xstring is
decoded exactly once (including literal escapes and Unicode surrogate pairs).

Only textual authoritative values and empty cells are admitted. Numeric/date/boolean/error
and formula-result cells are rejected with a precision/date explanation, regardless of
cached values. Text cells beginning with `=`, `+`, `-`, `@` remain literal. Exact decimals
must round-trip through the domain Double spelling without decimal-value loss; no rounding
or locale conversion is applied. Explicit manual strings retain their own domain rules.
Recognizable 15-significant-digit rounding of an existing coordinate/chainage/time is
rejected even if later retyped as text; arbitrary lost text precision cannot be proven.
An unchanged blank reuses the original typed object, preserving nil versus empty. Exact
reference seconds and millisecond ISO helpers must agree; changed time/zone/offset must
agree with the explicitly named zone's historical rule. No CRS/units/north conversion.

## Baseline and deterministic classifications

Reassemble source chunks by `(kind, record_id)` and contiguous integer index; verify
repeated metadata, count, lowercase SHA-256 and UTF-8 bytes. Decode typed schema-8
records, order correction chains by version, validate the complete graph, and reproject
it through the existing exporter. The reconstructed source chunks/JSON/metadata must
exactly match the v1 canonical projection. This detects missing records, unknown JSON
fields, wrong kind/point/version and broken history/evidence relationships. Required
worksheets and exact header key sets are checked against that same projection.

Reprojection retains the original observation, full revision chain, ordered original
measurements, J1–J5 interpretation/evidence links, tectonics, method-qualified Q/RMR/GSI,
coordinate provenance, catalogue, plans, photo contexts and attachment metadata. It never
interprets `source_records` as editable replacement objects. Workbooks are one-project
scopes; tests exercise both projects in a two-project local journal.

One result normally represents one point with its proposed geological children. Global
protected-table changes and duplicate groups have their own result rows. Counts are
logical records/groups, not physical Excel rows. Record order and field order are stable;
proposal digests sort logical table rows and ignore ZIP layout/shared-string indices.

| Classification | Rule |
| --- | --- |
| New | `record_action=new`; valid globally unused UUID `client_record_id`; base IDs/version/fingerprint and assigned timestamps empty; no measurement input; valid explicit existing parents and observation fields |
| Unchanged | Every point/child value equals its reconstructed projection and its full base still matches the current local generation; no candidate revision or duplicate point is proposed |
| Correction | Current full base matches; only supported observation/interpretation/tectonic/rating-input fields changed; duplicate representations agree; domain validation passes; nonblank correction reason |
| Duplicate | Identical logical row/chunk/link repeated; one logical value retained, explicit duplicate group shown |
| Conflict | Local revision/history/context/base diverges; new client/child UUID collides or proposed IDs collide across kinds; re-export/rebase required |
| Invalid | Bad UUID/input/parents, contradictory duplicate identity, inconsistent text/JSON/normalized helpers, invalid time/precision or domain validation failure |
| Unsupported | Protected identity/evidence/context/photo/derived fields edited; deleted point/child rows; unsupported coordinate source/provenance proposal or method transition |

Malformed packages, unsafe XML, wrong format/schema and incomplete/corrupt baseline fail
preparation entirely, with a Russian error and no publishable preview. Divergent duplicates
block the batch regardless of order; identical duplicates are reported without duplicate
new proposals. Missing rows never imply deletion. Orphan child rows are invalid.

For existing points compare original records with local immutable originals, complete
revision chains and the recomputed `FieldForge-Exchange-Base/1` fingerprint. Original
measurements and photo/attachment/history records are also checked against local evidence.
Parent/plan changes conservatively cause conflicts. Existing parents, creation/update and
correction metadata, conventions, measurement membership, child identity/method/time,
interpretation evidence, stored assessment outputs and baseline records cannot be edited.

Supported edits include picket/chainage/origin, field time, notes, intervals/position,
explicit manual coordinates, lithology, joint manual representations and geotechnical
inputs, tectonic descriptions and existing method-qualified rating inputs. Repeated
rating columns must agree with `input_json`; original/manual and normalized orientation
helpers must agree. Q/RMR input validation/evaluation calls existing verified services;
there is no new engineering formula. Original assessment time/method and saved results
remain protected workbook metadata. GSI method/time/final result remain unchanged when
proposing selection/range changes. SD changes require explicit manual provenance.
Manual coordinate proposals require source `manual`, metres and explicit CRS/axes/source
text; plan/manual-in-plan/calculated-Z provenance is preserved on unrelated edits and
cannot be fabricated through a coordinate correction. New sensor/photo/DXF records,
deletions, reassignment, new rating methods and mechanical calculations are unsupported.

SHA-256 and workbook UUIDs provide integrity/comparison, **not trusted authorship**. Local
immutable evidence must match. The format is not signed; it cannot establish the original
contents of a workbook for data absent from this device. Deliberate conversion to numbers
then back to text can erase evidence of coercion; lost digits cannot be reconstructed.
Do not use retyped numbers as a way to bypass a rejected numeric/date cell.

## Minimal B2c integration contract (design only)

1. Input is `MappingExchangePreview` plus the original validated workbook/proposal data:
   workbook UUID, semantic `proposalDigest`, captured generation UUID, metadata, per-point
   classifications/deltas and detached validated candidate values. Persist neither this
   transient model nor its generation UUID. Include baseline revision IDs/fingerprints and
   explicit `(workbook_id, client_record_id)` tokens from the workbook when constructing
   the future acceptance command. Candidate new UUID/time and unchanged joint revisions
   are **preview placeholders**, not final admission metadata.
2. After explicit user confirmation, reserve the existing `MappingStorageOwner` FIFO. Load
   its latest committed graph, refuse stale generation and all blocking results, recheck
   originals/history/fingerprints/parents/proposed UUIDs and domain graph validity inside
   that same synchronous transaction. Never trust an earlier green preview alone.
3. Build the entire batch in the existing transaction buffer. Existing observations append
   `MappingObservationRevision`; originals, timestamps, measurements and photo/DXF evidence
   remain unchanged. Assign admission correction ID/time/reason/author, previous revision
   and version; changed joint interpretations advance revision/time through existing rules.
   New observations receive collision-checked UUIDs and admission creation/update times,
   preserving the client token only in durable provenance. Revalidate every relationship.
4. Durable replay mapping must record `(workbook_id, client_record_id) → admitted point_id`
   and an accepted semantic proposal digest; existing corrections also need an operation
   token mapping to the admitted revision. Same token+digest is a no-op/replay; same token
   with different digest is a conflict. This must survive restart, export and complete
   backup/restore. In-memory IDs, filenames and source hashes are insufficient.
5. **Storage design gate:** schema 8 currently has no atomic durable admission ledger. Do
   not bolt on a separately saved sidecar. Before B2c, owner-review a ledger representation
   and its schema/compatibility policy or a recoverable transaction manifest that atomically
   couples graph+ledger and participates in full backup/restore. B2b introduces neither.
   If a schema change is required, report it and obtain the owner decision; do not silently
   migrate the experimental database.
6. Audit provenance must retain workbook/proposal IDs/digest, accepted field deltas, source
   export metadata, base identities, reviewer/reason, admission timestamp, resulting point/
   revision IDs and parser/format version. Do not claim authorship authentication. Preserve
   original evidence and separate imported interpretation from field measurement.
7. Publish only after one recoverable atomic graph+ledger commit. Validation/collision/
   conflict/cancellation before admission leaves everything unchanged. IO failure rolls
   back the complete batch or recovers a documented pending manifest before publication;
   never report partial success. Preserve current `.previous`, external-change protection,
   backup state and independent-measurement compatibility. Fault-injection/restart tests
   are required when this write design is implemented.

B2b has no durable replay state because it performs no admission: repeated unchanged books
classify unchanged; repeated unaccepted new proposals stay proposals. It makes no claim to
recognize future admitted client tokens before B2c's ledger exists.

## Verification and qualification

Synthetic fixtures cover two projects, revisions, J1–J5, measured evidence, manual location
provenance, exact dates/decimals, Q/RMR/GSI, unchanged/corrected/new/duplicate/stale inputs,
source corruption, reordered sheets/rows, shared strings and DEFLATE desktop-style saves,
formulas/cached results, coercion, relationships, ZIP/XML limits, cancellation, generation
staleness and unchanged on-disk journal/directory inventory through failure/cancellation.
No private field data. Files-provider and real Excel UI/physical-device qualification remain
in #24; synthetic Excel-style rewrites are not a claim of testing Microsoft Excel itself.
No screenshots/runtime launch are required for this compile-level verification.

Final verification (2026-10-29):

```sh
swift test --filter MappingExchangePreviewTests
# 15 tests, 0 failures; /tmp/fieldforge-b2b-tests.log

xcodebuild -project FieldForge.xcodeproj -scheme FieldForge \
  -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/fieldforge-a5-derived CODE_SIGNING_ALLOWED=NO build
# Incremental Debug, arm64 + x86_64; /tmp/fieldforge-b2b-simulator.log
```

Project regeneration was byte-identical. No full SwiftPM/Xcode regression, performance
benchmarks, fixture generators, unrelated suites, runtime UI or physical Files/Excel
provider tests were run. The existing AppIntents metadata-extraction notice is unrelated.

Verification-budget deviations were limited to concrete new-code failures/concerns: the
first sandboxed manifest attempt could not access Swift's module cache; compilation was
interrupted while a long expression stalled type checking and the expression was split;
a test helper named `zip` initially shadowed `Swift.zip`; content-type lookup initially
misread `_rels/.rels` as having no extension. Those attempts were corrected and the same
focused suite rerun. Review then found ambiguous duplicate JSON keys and recognizable
15-significant-digit Excel conversion after retyping as text; strict JSON preflight and
precision checks were added with a focused case, including missing multi-chunk evidence.
A final concrete defect could substitute a point's ten-metre convention for an existing
interval's nil/legacy convention on correction; the convention is now retained explicitly,
with a dedicated regression case. The incremental Simulator build was repeated once for
that final production change. No unrelated tests were added to these runs.

Lifecycle follow-up verification (2026-10-30):

- `swift test --filter 'MappingExchange(PreviewCoordinator|FileRead)Tests'`: initial
  12 coordinator + 3 Files tests passed. After adding the closed/reopened-appearance
  guard and its specific case, `swift test --filter MappingExchangePreviewCoordinatorTests`
  passed all **13** coordinator tests; Files code was unchanged (**3** passing tests).
- `swift test --filter MappingExchangePreviewTests`: **15 passed**, unchanged parser/
  classification suite. **31 distinct passing tests** across the three focused classes.
- One incremental generic iOS Simulator Debug build, arm64/x86_64, signing disabled:
  **BUILD SUCCEEDED**; Complete Strict Concurrency Checking, no source warnings. Only
  the existing AppIntents metadata-extraction notice remains.
- `git diff --check` clean; deterministic project regeneration verified. No full suites,
  benchmarks, unrelated generators, real Excel/Files providers or runtime UI testing.
- Logs: `/tmp/fieldforge-b2b-races-tests.log`,
  `/tmp/fieldforge-b2b-races-coordinator.log`, `/tmp/fieldforge-b2b-races-preview.log`,
  `/tmp/fieldforge-b2b-races-simulator.log`.
