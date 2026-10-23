# A4: serialized off-main mapping storage (#35)

## Execution and transaction boundary

`MappingModel` remains MainActor-owned observable presentation state. The application
has one `MappingStorageOwner`, backed by a private FIFO DispatchQueue. A queue block
never suspends: an actor alone would not provide that guarantee across `await`.
`@Sendable` closures explicitly cross the execution boundary; the owner's unchecked
Sendable conformance relies on queue confinement of its committed snapshot and
working store. [A5](swift6-concurrency-a5.md) replaces workflow/store transfers with
value snapshots and the photo store's unchecked conformance with compiler-checked
Sendable plus a synchronized test hook.

On admission, the model assigns an operation UUID, freezes its complete workflow
input and publishes `saving(id)`. Durable commands and volatile draft edits are
blocked until reconciliation. The owner rebases the command on its latest committed
journal, using a small in-memory `MappingStore` buffer for workflow `commit` calls.
Only after the whole synchronous command returns successfully does it call the
original file store once. A throw after a buffered workflow commit therefore cannot
leave disk ahead of the UI. This also makes several logical changes in one command
one atomic journal replacement. Attachment finalization must be outside this block.

`FileMappingStore` retains its existing implementation: schema-8 full validation,
append-only evidence/history checks, previous-byte decode, sorted/pretty JSON,
encoded round-trip equality, both external-change comparisons, exact `.previous`
write and atomic current-file replacement. No migration, reset, new stored fields,
backup format or measurement-journal change. The buffer is volatile, not a database.
Only a successful file save advances the owner's graph and MainActor snapshot.

UI entry-point tasks await the owner; no critical write is launched in a detached
or fire-and-forget persistence task. The queue owns admitted work and its checked
continuation through completion, independently of the requesting task's lifetime.

## Ordering and publication policy

The UI admits one durable operation at a time. Conflicting requests are **disabled
or explicitly refused with a retry message**, not silently queued or dropped. The
storage queue also serializes preparation, recovery scans and thumbnail mutations.
Its transaction API rebases queued inputs on the last committed graph; FIFO tests
exercise two requests with the same old snapshot and verify no lost updates.

| Request | Policy |
| --- | --- |
| Save, then change excavation | Finish/reconcile save in its frozen context; while saving, reject the switch. A subsequent switch preserves the saved point. |
| Change horizon during save | Explicit busy error. Retry after reconciliation; dirty drafts still use existing park/return confirmation. |
| Two rapid saves | First admitted; second receives a busy error. A completed draft UUID is an idempotent no-op, never a save of the next empty draft. |
| Observation/photo correction | Same admission gate; retain local editor inputs on failure. After admission, existing baseline-revision checks still reject stale corrections. |
| Photo import and context change | Active draft picker/provider sessions block durable operations until receipt/cancellation, preventing callback loss during snapshot publication. Saved-point imports retain their frozen point revision; a busy commit retains the exact operation and bytes for retry. |
| DXF registration during another operation | Preparation uses the FIFO owner. Registration receives a busy error; its staged original/manifest and frozen horizon remain retryable with the same UUIDs. |
| Retry | Draft/photo/plan identities remain stable. Already committed imports are verified no-ops. Failed correction UUIDs have no committed record; stale successful correction retries are rejected by their baseline. |
| Export during save | Export the last committed value captured when opening the export screen, explicitly labelled in Russian. Pending saves and later edits are excluded. |

The model exposes `idle`, `saving(id)`, `committed(id)` and `failed(id, message)`.
No other durable command can start before the current result publishes, so an older
completion cannot overwrite a newer UI snapshot. Volatile UI callbacks use the
same admission guard through `performThrowing`; refusal propagates to the point or
geology editor rather than dismissing it as a successful acceptance.
Capture/context/editor controls are disabled as necessary; the existing observation-success alert and actionable
errors remain. Saving uses small text rather than adding a spinner to fast saves.

## Cancellation and attachment recovery

Admission is the cancellation boundary. Even a cancelled caller's admitted command
runs to completion, including work waiting in the queue. Cancellation does not
interrupt an atomic write, discard its result or skip MainActor reconciliation.
This trades prompt cancellation for an unambiguous committed/failed result. Pure
export preparation/output retains its existing independent cancellation policy.

Photos use: stable operation + retained bytes → durable intent → staging/promotion
and size/SHA-256 verification → journal commit → thumbnail/intent finalization.
Draft photos and their first point share one JSON commit. Any preparation or JSON
failure preserves the complete draft, live bytes, intents and all written originals;
no uncommitted graph is published. Live bytes are retained until successful commit,
including when a verified original already exists after a failed JSON save. After
success, thumbnail/finalization failure is a recoverable warning, not a failed point
save. Retry uses the same operation and rechecks the original.

DXF preparation retains stable UUIDs and import time across retries, refuses to
replace a different existing intent, and verifies existing bytes rather than
rewriting originals. Registration rechecks size/SHA-256 and parsing before committing
a reference. Missing-original recovery accepts only the same original bytes via the
pending-import source-file action. Mismatching/corrupt existing files are preserved
for reviewed recovery. Finalization only removes redundant operation manifests.

Filesystem originals and journal JSON remain separate transactions. A process stop
before JSON commit may leave recoverable files/intents; no orphan cleanup occurs.
A draft that existed only in memory is still not restored after process termination.
External tampering after verification cannot be prevented by the app; existing
read/export checks continue to report missing or damaged originals.

## Off-main work and remaining MainActor costs

Moved: application journal load, complete workflow command validation, correction
validation, file encoding/decoding, backup/current I/O, photo acceptance/hashing,
staging/promotion/retry, recovery-manifest scans, thumbnail writes, camera file
reading/JPEG fallback encoding, DXF preparation/registration and recovery. Export
table preparation and output already ran off main and continue to consume immutable
committed values without changing formats. Read-only plan/image display workers may
run independently; they cannot commit journal or original attachment mutations.

Remaining MainActor work: short input/editor validation and presentation formatting,
context/plan lists and preferences, effective-observation queries/filtering/sorting,
SwiftUI body/layout work, snapshot publication and value destruction. Application
Support directory lookup remains synchronous at startup. The Photos provider must
copy its temporary URL before its callback returns; it remains on the provider's
callback executor. This is not physical-device frame-time or camera qualification.
Whole-journal JSON latency and memory costs are retained, not optimized away.

## Focused verification

Tests use isolated temporary directories, expectations and semaphores with timeout
safeguards; no sleep-based correctness assertions. They cover FIFO rebasing, exact
previous bytes, schema-8 reopen, external modifications, buffered rollback, busy
saves/context/revisions/DXF, stale publication prevention, cancellation reconciliation,
photo context freezing and original-file recovery. Existing photo suites cover every
attachment checkpoint, actual backup failure, metadata histories and idempotent retry.

The opt-in `MappingResponsivenessTests` reuses only the A2 1,000/5,000 fixtures for one
save each. It asserts file-store load/save execute off main, proves a MainActor probe
runs during a gated save, and samples a 16 ms main-queue heartbeat while measuring
end-to-end save latency. Heartbeat maximum gap includes the sampling interval and
scheduler noise: it is responsiveness instrumentation, not an exact blocking-time
measurement or a total-save speedup claim. Fixture creation/seed/load are excluded
from the save metric; the brief synchronization gate is included.

Final Release samples on this macOS x86_64 host:

| A2 fixture | Save latency | Main heartbeat ticks | Maximum heartbeat gap |
| --- | ---: | ---: | ---: |
| 1,000 observations | 610.8 ms | 39 | 20.6 ms |
| 5,000 observations | 3234.9 ms | 203 | 23.2 ms |

No end-to-end speedup over A3 is claimed. These are single samples, not medians or
physical iPhone results. The earlier development sample was repeated only after the
transaction-buffer/admission changes; the full A2 workload was never run.

Targeted Debug SwiftPM classes: `MappingConcurrencyTests`, `MappingTests`,
`P2MappingTests`, `P33RevisionTests`, `P41PhotoTests`, `P42DraftPhotoTests` and
`PlanRevisionManagementTests`: **90 distinct cases passed across the affected
runs** (the final recovery/concurrency/plan rerun passed all 28). Initial sandbox
ImageIO failures reproduced the A3 environment limitation; affected photo tests ran
outside that sandbox. One photo-retention expectation and active-picker context
tests were updated for the stricter new contract. The seven new concurrency cases
use deterministic barriers; existing original-measurement tests were not modified.
The final focused Release responsiveness test passed for both fixture sizes.

Commands use `SWIFTPM_MODULECACHE_OVERRIDE=/tmp/fieldforge-a4-module-cache` and
`CLANG_MODULE_CACHE_PATH=/tmp/fieldforge-a4-clang-cache`:

```sh
swift test --disable-sandbox --filter 'MappingConcurrencyTests|MappingTests|P2MappingTests|P33RevisionTests|P41PhotoTests|P42DraftPhotoTests|PlanRevisionManagementTests'
FIELD_FORGE_STORAGE_A4=1 swift test --disable-sandbox -c release --filter MappingResponsivenessTests
xcodebuild -project FieldForge.xcodeproj -scheme FieldForge -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/fieldforge-a4-derived CODE_SIGNING_ALLOWED=NO build
```

The generic iOS Simulator build passed for arm64/x86_64 with signing disabled;
follow-up compilation covered affected UI closure/startup fixes. The first sandbox
build could not reach CoreSimulator for asset compilation; the successful build ran
with runtime-service access. No Swift concurrency diagnostics remain in the Debug
app build (the unrelated AppIntents metadata notice remains). Xcode generation was
regenerated and checked deterministic. Full SwiftPM/Xcode/Simulator UI regression,
physical-device/camera profiling, unrelated engineering/DXF audits and stress suites
were deliberately skipped. No device journals or original assets were accessed.

PR #65 admission review follow-up: the DXF request callback, plan fallback and
geology acceptance callbacks now share the model's throwing volatile admission.
One additional barrier-based test proves coordinate refusal during an in-flight
save, unchanged draft/journal state and the existing XY/Z/manual-override acceptance
rules after completion. Six affected tests and one generic iOS Simulator Debug
build passed; no regression suite, benchmark or subagent review was run.
