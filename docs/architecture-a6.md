# A6: repository contracts and presentation queries (#37)

Based on main `f21a860` (merged A5 / PR #66), 2026-10-23. Schema 8, JSON
fields, engineering methods, export formats and original-measurement storage are
unchanged. See the dependency diagram in [architecture](architecture.md#a6-repository-and-presentation-contracts).

## Problems confirmed before implementation

- Journal body accessed its effective/filter/sort property for count, empty state
  and rows, plus another effective scan for the project count. Each row scanned
  revision history and context UUIDs again.
- Observation detail repeatedly resolved the same effective revision; both original
  reading sections rebuilt a journal-wide measurement dictionary.
- Plan overlay resolved all effective observations and traversed the compatibility
  graph per point, then repeated the query for Canvas/accessibility/interaction.
- Wedges rebuilt its sources through multiple computed properties and scanned all
  revisions per saved source. Export's selection count resolved all effective
  observations on each evaluation despite already owning a frozen journal.

These are consumers of an already adequate concrete repository boundary. No new
`ProjectRepository` protocol, generic container or writer is justified.

## Ownership and repository contract

| Owner | Responsibility |
| --- | --- |
| `MappingStorageOwner` | Private FIFO executor and working store. Non-suspending commands rebase on its current committed generation. One authoritative file save after successful buffered commands; then return the checked-Sendable snapshot. Cancellation still reconciles. |
| `MappingModel` | MainActor admission, busy/error state, publication and disposable active-plan preferences. Presentation reconstruction shares indexes; it never builds them here. |
| `MappingWorkflow` | Domain commands, capture editing, pending context and parked drafts. Production durable commands execute on the FIFO queue; admitted volatile edits use its write-refusing presentation instance on MainActor. |
| `MappingWorkflow.Snapshot` | Transfer the immutable committed generation plus draft, pending context and parked drafts. No working store crosses isolation. |
| `MappingCommittedSnapshot` | Immutable journal and read indexes with checked Sendable. No mutable members, storage handle, Codable or persistence operations. |
| Screens | Sheets, correction/joint/coordinate requests, temporary fields, filters, plan pan/zoom/picking, Wedges parameters and export/share lifecycle. |

`MappingStore` stays the synchronous load/save primitive, with the existing
transaction buffer and write-refusing presentation adapter. There is no new
persistence route. Full schema validation, `.previous`, append-only checks, atomic
replacement and external-change guards remain in `FileMappingStore` unchanged.

Durable state is committed evidence/history and attachment references. Volatile
application state is the active/parked drafts, pending context, in-flight save and
retained photo intents/bytes. Screen-local edits publish through the existing
identity and admission checks. Photos keep their frozen point/revision context and
FIFO staging/retry flow; no screen state was moved into a global observable model.
Sensor/HOLD, AR distance and Foundation-only engineering services are untouched.

## Derived-data lifecycle

1. Workflow load builds one immutable committed generation. Each successful workflow
   commit builds its replacement on the same executor. Buffered intermediate
   generations stay private; a failing command/file save discards them. Only the
   final durable success advances the owner's generation and MainActor publication.
2. The generation retains the exact journal used for its indexes. Effective records
   retain original array order; latest revisions use journal order. UUID indexes
   cover observations, latest revisions, contexts, measurements and plans. Project
   and horizon membership use integer offsets into one effective-observation array.
3. Every committed change replaces the whole generation, including corrections,
   context, plan management and metadata changes. This intentionally favors a small
   deterministic rule over selective invalidation. Construction is linear in table
   sizes and runs off main in production. Synchronous domain fixtures remain usable.
4. Draft edits, pending context, photo receipt and display-only plan preferences
   share the existing generation. Transfer/publication does not copy/reindex the
   whole journal. Failed saves retain the identical generation and draft.
5. Journal query filters/sort run once per body from indexed project membership;
   project counts and row revision/context lookups use indexes. Detail resolves its
   record/readings once per body; historical snapshots still use original evidence.
6. Plan queries use horizon membership and a query-local compatibility dictionary:
   evaluate the unchanged compatibility method once per encountered source-plan UUID.
   Each body shares one result among drawing, accessibility and picking. Revision,
   filter or committed-generation changes synchronously recompute that result; there
   is no asynchronously published overlay to arrive out of order. The existing
   loader/request identity and selection restrictions are unchanged.
7. Wedges constructs sources once per body from committed context membership and
   indexed latest revisions, adding the live draft separately. Joint-selection
   reset, north checks, geometry and visualization behavior remain unchanged.
8. Export's `@State` retains one committed generation at opening; its selection
   count uses that generation. Preparation/serialization still take the frozen
   journal through their existing detached workers. Later draft edits, corrections
   and context changes cannot alter an open export.

Identity is an in-memory immutable generation, not a new database revision number.
No cache fields enter schema 8. Query-local results need no invalidation framework.
Indexes do not replace validation; duplicate IDs are still authoritatively rejected
by the store. Small context/plan option lists, full historical details and export
serialization keep their existing straightforward domain queries.

## Query evidence

A2 recorded effective-all at 4.297 ms and effective+filter at 87.237 ms for 5,000
points; A3 effective-all was 3.614 ms. Those are historical Release host samples,
not new A6 measurements. They motivated eliminating repeated presentation work;
the A2/A3 benchmark/stress suites were not rerun.

| Path | Before | After |
| --- | --- | --- |
| Journal body | Four O(N+R) resolutions, three filter/sorts and one project filter | One project membership read/filter/sort; O(1) total count. Resolution/index construction moves to commit/load. |
| Detail | Repeated O(N+R) effective lookup; repeated O(M) reading maps | O(1) effective lookup and O(m) ordered reading lookups for this point |
| Wedges | Repeated whole-journal resolution and O(K×R) latest-history scans | One horizon/context pass and O(1) latest-revision lookup per selected source |
| Plan overlay | Whole-journal resolution and compatibility traversal per point | Horizon pass, O(1) source lookup and compatibility once per distinct encountered source revision, once per body |
| Export count | O(N+R) resolution followed by global filtering | Filter indexed project members from its retained generation |

N = points, R = revisions, M = all measurements, m = point measurements,
K = context points. Filter/sort and compatibility costs remain; no claim of linear
plan compatibility itself is made.

One paired Debug SwiftPM diagnostic reused only A2's deterministic **100-point**
fixture (10 corrections, four projects, 200 originals). Thirty samples per shape
consumed the full resulting records/count/empty/project-count values and checked
exact equality outside timing. `MappingJournalQueryTests` also compares all indexed
records, latest revisions, readings, project/context scopes and plan overlays with
the previous APIs, including picket/date/sort combinations.

| Journal body query shape | Median, n=30 |
| --- | ---: |
| Previous count/empty/rows + project count | 2.815 ms |
| Shared result + indexed project count | 0.791 ms |

One index-construction + detached-task round trip took **1.166 ms** for this fixture;
it is outside the render timing and is not a pure indexing measurement. Production
construction runs on the FIFO queue, not on MainActor. This is a limited host Debug
query comparison, not a SwiftUI runtime trace, Release/device benchmark, FPS claim
or end-to-end save speedup. No performance threshold depends on these timings.

## Verification

One focused SwiftPM Debug run: **17 tests passed, zero failures**, including two new
tests and additional generation assertions in existing FIFO/failure/rollback tests.
Coverage: exact query equality, correction invalidation, snapshot sharing, frozen
export contents, rapid excavation/project switching and draft parking, rejected
presentation writes, failed saves/external-file changes, cancellation reconciliation,
FIFO rebasing, provisional-command rollback, compatible/incompatible plan revision
switching, stale coordinate callbacks and Wedges revision/draft provenance. Small
fixtures and isolated temporary files only; no timing sleeps or device journals.

```sh
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/fieldforge-a5-module-cache \
CLANG_MODULE_CACHE_PATH=/tmp/fieldforge-a5-clang-cache \
FIELD_FORGE_UI_QUERIES_A6=1 swift test --disable-sandbox --filter \
'MappingJournalQueryTests|MappingConcurrencyTests/testCommittedReadGeneration|MappingConcurrencyTests/testPublishedWorkflow|MappingConcurrencyTests/testFIFOTransactions|MappingConcurrencyTests/testBusyRequests|MappingConcurrencyTests/testFailedSave|MappingConcurrencyTests/testRevisionRejected|MappingConcurrencyTests/testCommandThrow|ThirdIPhoneReviewTests/testConfirmedCrossRevision|ThirdIPhoneReviewTests/testQualifiedMetadata|ThirdIPhoneReviewTests/testDirectActivePlan|P33RevisionTests/testPlanMove|P33RevisionTests/testPlanVersionSwitch|WedgeW1Tests/testReadOnlySource|MappingCSVExportTests/testPreviewFiles'
```

Project inventory regenerated for the new production file; a second generation was
byte-for-byte identical. Swift 5 and Complete Strict Concurrency Checking remain
enabled on all Xcode targets and SwiftPM targets. No new unchecked conformance or
warning suppression. SwiftPM emitted zero source concurrency diagnostics (four
sandbox user-cache warnings are unrelated).

One final incremental generic iOS Simulator Debug build **succeeded**, using the
existing A5 derived-data directory, with signing disabled. Zero concurrency warnings
or errors; the single unrelated AppIntents metadata-extraction notice remains.

```sh
xcodebuild -project FieldForge.xcodeproj -scheme FieldForge -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/fieldforge-a5-derived CODE_SIGNING_ALLOWED=NO build
```

Build/test logs: `/tmp/fieldforge-a6-simulator.log` and
`/tmp/fieldforge-a6-focused.log` (local, not committed).

## Deferred limits

Every committed graph change rebuilds linear in-memory indexes; open exports retain
older generations. This adds memory and off-main work, deliberately trading selective
invalidation complexity for consistency. Plan compatibility still runs during a body
update, now once per source revision; large plan collections may merit a separate
measured change. Full-history, photo metadata and export table queries remain as
before. Whole-journal JSON costs and physical-device frame time remain unqualified.

A future database proposal needs its own measured workload, owner approval and
recovery/migration design; A6 neither requires nor implements it. Memory-only drafts
can still be lost on process termination. Full regression/UI suites, unrelated
engineering tests, large storage/DXF benchmarks and physical sensor/share-sheet
qualification were deliberately skipped.
