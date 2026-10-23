# A5: strict concurrency audit (#36)

Audited from main `c222f26` after A4 / PR #65, 2026-10-23. Schema 8,
original-measurement persistence, engineering algorithms and export formats remain
unchanged. No migration, reset, runtime dependency or device-data operation.

## Compiler and diagnostics

Xcode **26.6 (17F113)**, Apple Swift **6.3.3**, iOS Simulator SDK **26.5**;
iOS deployment target remains **17.0**, SwiftPM macOS target **13**.
Keep **Swift 5 language mode** (`SWIFT_VERSION = 5.0`, SwiftPM tools 5.9).
The deterministic generator sets `SWIFT_STRICT_CONCURRENCY = complete` for Debug
and Release on app, unit-test and UI-test targets. Both SwiftPM targets enable
`StrictConcurrency`, the complete-checking feature in this language mode.

Counts below count diagnostic headers, not repeated source excerpts. Architecture
duplicates are stated separately; suggestions to suppress warnings are not applied.

| Check | Baseline | Final |
| --- | ---: | ---: |
| Whole app, Swift 5 complete frontend typecheck | 28 | 0 (intermediate frontend check) |
| SwiftPM test compilation, complete checking | 14 | 0 |
| Whole app, final Swift 5 complete object generation | Not collected | 0 |
| Whole app, final Swift 6 SIL generation | Not collected | 0 errors / 0 warnings |

Baseline frontend files: `MappingStorageOwner.swift` (3 non-Sendable store/workflow
captures); `HorizonPlansView.swift` (15 DXF/prepared-import transfer diagnostics);
`MappingExportView.swift` (8 export-owner transfer diagnostics, 1 calendar isolation
diagnostic); `MeasurementView.swift` (1 callback conversion diagnostic).
SwiftPM reported 12 export-owner transfer diagnostics plus 2 module-import
suppression suggestions in `MappingCSVExportTests` / `MappingXLSXExportTests`.
That incremental baseline compiled tests; common production sources were also
covered by the app frontend inventory. These are **not** a baseline full-codegen
warning count.

The single Xcode Simulator build succeeded, but code generation exposed 8 additional
unique diagnostics (16 emissions across arm64/x86_64): three nonisolated deinits,
four new AR session-reference captures, and one CoreMotion suppression suggestion.
All were subsequently resolved with isolated deinits and value-only callback
identity/status. Final full-source Swift 5 object generation and Swift 6 SIL
generation passed. **The app was not rebuilt/relinked after those corrections**,
to honor the one-Simulator-build budget. The build also had the unrelated
AppIntents metadata-extraction notice. No warning suppression was added.

## Ownership and fixes

- `MappingModel`, acquisition/HOLD, app state, photo/plan coordinators and wedge
  presentation remain MainActor-owned. Queue results reconcile there even when an
  admitted caller is cancelled. The existing busy gate prevents stale publication.
- `MappingStorageOwner` now retains its working `MappingStore` privately. Only
  `MappingWorkflow.Snapshot` (journal, draft, pending context, parked drafts) crosses
  the queue boundary. Published workflows have a write-refusing presentation store;
  accidentally calling a durable workflow command from a volatile UI callback
  fails before publication or I/O. Synchronous standalone domain tests keep their
  existing store interface; the fixture initializer explicitly hands off its store.
- `run`, transaction and presentation `persist` require Sendable results. Snapshot
  members, photo operations/received bytes, prepared DXF documents and export tables
  have compiler-checked Sendable conformances. The shared BVH has immutable stored
  members, with query metrics local to each query; its algorithms are unchanged.
- The private FIFO queue still executes each entire command without suspension:
  workflow commits buffer locally, then one authoritative save succeeds before the
  committed journal advances. File validation, `.previous`, atomic replacement and
  both external-change comparisons are unchanged. No second writer was introduced.
- Photo/DXF mutations, including staging, promotion, completion and recovery, remain
  on that queue. Freeze context, UUIDs and bytes before admission. Cancellation
  after staging does not abandon the commit or its reconciliation; failed commits
  retain live bytes/intents/originals for the same-identity retry. Read-only display
  and export workers can read immutable originals independently.
- `ManagedPhotoStore` is now checked Sendable: its root is immutable and its
  `@Sendable` failure hook uses `OSAllocatedUnfairLock`. Copy the hook under the lock,
  invoke outside it. The lock does not authorize parallel filesystem mutations.
- AR delegates retain the explicit `.main` delivery contract, but transport only
  `ObjectIdentifier` and a value status into actor isolation. Each restart gets a
  new ARSession identity; stopped/previous sessions cannot publish callbacks.
  Only the matching interrupted session can request recovery; closing/backgrounding
  cancels recovery. Frame freshness and all distance math remain unchanged.
- Core Motion already converts framework objects into SensorSample values before
  MainActor publication and checks its generation token; preserve that guard.
  Distance/heading timers now reject queued work from earlier generations.
  Three `isolated deinit` annotations keep timer/motion cleanup on MainActor.
  An iOS-17 compiler probe emitted the MainActor deinit back-deployment helper;
  physical iOS-17 teardown was not exercised.
- Export workers continue to own committed value snapshots and isolated output
  directories. Cancellation propagates to the worker and error paths remove only
  its output. Share dismissal releases its package reference rather than explicitly
  deleting files another share owner could still retain; deinit cleans the directory
  when the last owner releases it. No source originals are removed.
- The calendar callback freezes its Calendar value; the measurement Binding uses an
  explicit UI closure. No navigation, editing, classification or UI text changes.

`Task.detached` remains limited to read/parse/decode or export preparation/output,
with immutable inputs. Provider file URLs are copied inside their callback/security
scope. NSFileCoordinator captures are synchronous callback-local state, not shared
mutable import state. Durable work uses the admitted FIFO owner, not detached tasks.

## Remaining unchecked boundaries

One production `@unchecked Sendable` remains: **MappingStorageOwner**. Its private
store and committed graph are accessed only inside its private serial queue's
non-suspending blocks, except initialization before publication. Neither the store
nor a transaction buffer escapes. Closures/results are checked Sendable. A default
actor does not express the established FIFO DispatchQueue contract; replacing it
with a custom executor or new locking layer would enlarge A5 without strengthening
the already serialized transaction. Maintain this invariant when extending it.

The existing four `MainActor.assumeIsolated` delegate bridges rely on ARSession's
explicit `.main` delegateQueue. They do not schedule a framework reference across
an asynchronous hop. No `nonisolated(unsafe)` or `@preconcurrency` was added.
Test-only unchecked types are GatedMappingStore (queue-confined file, locked hook)
and the existing MainQueueHeartbeat (locked counters; sampled after its save).

## Focused verification and limits

**16 distinct selected Swift tests passed** across the initial run and targeted
repairs: four existing A4 cases (FIFO/previous bytes, cancellation/busy context,
buffered rollback, DXF recovery/repeated registration), two new owner/photo cases,
one new callback-lifetime case, three CSV lifetime/cancellation cases, five photo
import/retry cases, and one photo-ZIP cancellation case. The initial run had one
failure: a pre-existing assertion expected live bytes to be released after a failed
journal commit, contrary to the A4 implementation/contract. Corrected it to assert
retained exact bytes and reran only that case and the edited export-lifetime case
(2/2). After changing callback input to value identity, reran only its case (1/1).
New concurrency tests use barriers/expectations, never timing sleeps.

Commands used `SWIFTPM_MODULECACHE_OVERRIDE=/tmp/fieldforge-a5-module-cache` and
`CLANG_MODULE_CACHE_PATH=/tmp/fieldforge-a5-clang-cache`:

```sh
swift build --disable-sandbox --build-tests -Xswiftc -strict-concurrency=complete
swift test --disable-sandbox --filter '<selected class/test names above>'
xcodebuild -project FieldForge.xcodeproj -scheme FieldForge -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/fieldforge-a5-derived CODE_SIGNING_ALLOWED=NO build
# Full app source list from rg --files FieldForge -g '*.swift', sorted:
xcrun swiftc -c -whole-module-optimization -D DEBUG -swift-version 5 \
  -strict-concurrency=complete -module-name FieldForge \
  -target x86_64-apple-ios17.0-simulator -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
  -module-cache-path /tmp/fieldforge-a5-ios-module-cache <sources> -o /tmp/fieldforge-a5-final.o
# Same source/SDK arguments, -emit-sil instead of -c and -swift-version 6:
# output /tmp/fieldforge-a5-final.swift6.sil
```

The initial SwiftPM manifest sandbox was unavailable; use `--disable-sandbox`.
Photo tests and the single Xcode build used host ImageIO/CoreSimulator access;
fixtures stayed in isolated temporary directories. SwiftPM user-cache environment
warnings are excluded from source-concurrency counts. Project regeneration was
byte-for-byte deterministic. Full regression/UI suites, stress/benchmarks, unrelated
engineering/DXF tests and physical sensor/share-sheet validation were deliberately
skipped. No final-source second Simulator build or Swift-6-mode test run is claimed.

Production sources pass a Swift 6 compiler/SIL check with no remaining diagnostics;
retain Swift 5 + Complete until Xcode test/UI targets and runtime teardown are
qualified in that language mode. For A6 / #37, keep the value-snapshot ownership
boundary, consider narrowing the generic workflow command surface only for actual
feature needs, and address repeated MainActor journal queries using the existing
A2/A3 evidence. A6 is not implemented here. Process termination can still lose
unstaged memory-only drafts; journal/attachment writes remain separate recoverable
transactions. Physical measurement accuracy remains unvalidated.
