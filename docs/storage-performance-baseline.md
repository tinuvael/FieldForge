# A2 storage performance baseline (#33)

Before-refactor baseline of `MappingJournal`, `MappingWorkflow`, `FileMappingStore`
and `MappingJournalQuery`, based on main `ec4b72680f18350e137236f2c9b851a64c57ead3`.
Production code, schema 8 and storage formats are unchanged. Follow-up:
[#34](https://github.com/tinuvael/FieldForge/issues/34).

## Reproduction

On macOS with the repository's Apple Swift toolchain:

```sh
FIELD_FORGE_STORAGE_BENCHMARKS=1 swift test -c release --filter MappingStorageBenchmarkTests
```

The measured run used writable compiler caches in this restricted workspace:

```sh
CLANG_MODULE_CACHE_PATH=/tmp/fieldforge-storage-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/fieldforge-storage-swift-cache \
FIELD_FORGE_STORAGE_BENCHMARKS=1 \
swift test --disable-sandbox -c release --filter MappingStorageBenchmarkTests
```

This is deliberately opt-in: the single selected XCTest took **3,568.107 s
(59.5 min), 0 failures**. Release compilation took 128.67 s separately.

## Environment and fixtures

Measured 2026-10-22, 17:03:01–18:02:29 UTC, on macOS 26.6.2 (25G83), x86_64;
reported Intel Core i7 2.3 GHz, four physical/eight logical cores, 32 GiB RAM.
Xcode 26.6 (17F113), Apple Swift 6.3.3 (`swiftlang-6.3.3.1.3`,
`clang-2100.1.1.101`), SwiftPM Release optimization. This is a development-host
baseline; background load/thermals and storage media were not controlled.

Runtime fixtures have deterministic UUIDs/dates/values and four projects, horizons,
excavations and plan references. Every point has two originals: manual grid-north
and synthetic sensor with its separate north reference. XY is plan-derived in a
synthetic local metre frame; Z is unknown. Every tenth point has J1–J5, existing
published-method Barton Q, input-only RMR89 and one photo reference. Every twentieth
point has two notes corrections. Half the photos reference version 3, half version 1.
This mixed profile does not characterize dense/deep histories on every point.
Photo/DXF metadata are reference-only, with artificial hashes; no binary image/DXF
I/O, decoding or parsing is measured. All files live in one UUID-named temporary
directory, removed on normal completion. An interruption can leave synthetic temp
files. No app-support paths or independent measurement journals are opened.

| Initial points | Revisions | Originals | Joint sets | Photos | JSON bytes |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 100 | 10 | 200 | 50 | 10 | 559427 |
| 1,000 | 100 | 2,000 | 500 | 100 | 5554112 |
| 5,000 | 500 | 10,000 | 2,500 | 500 | 27769912 |

## Method and results

- Serial synchronous work on `@MainActor`, one process, ascending sizes. Monotonic
  `DispatchTime.uptimeNanoseconds` measures wall latency. Setup, result checks and
  write-workflow initialization are outside timing; each sample has an autorelease
  pool. No warm-up samples are discarded. Results are consumed/checked after timing.
- Three expensive-operation samples, ten JSON samples, 100 query/atomic-write
  samples. Median is the middle value (middle-pair mean for even n). p95 is nearest
  rank, only at n=100: a descriptive within-process tail, not a confidence bound.
- Cold store load constructs a new store, reads, decodes and fully validates.
  **OS caches are not flushed**: cold application state, not cold disk/device.
  Read+decode and decode-only omit validation; do not subtract their medians to
  estimate disk latency. Base-graph/revision-only rows attribute existing functions.
- Project-sort uses pre-resolved points. Combined filtering includes effective
  resolution, project/horizon/excavation, picket text, inclusive UTC calendar dates
  and chainage sorting. Chainages are already ascending, so worst-case sort order
  and many-project/plan workloads are unmeasured. Single lookup scans for the last,
  unrevised original through both global revision and observation arrays.
- Append-only membership replays the observation/measurement/revision/photo/
  attachment `allSatisfy { contains }` lookup shape on an unchanged journal. It
  excludes decode, plan/lithology checks and I/O. Shared value storage can cheapen
  matching-element equality relative to an independently decoded previous journal.
- Each write case uses a fresh baseline file/store, then three successive commits:
  new saves add one point/manual original each, revisions add one correction each,
  contexts alternate projects; growth is at most three points/revisions per case.
  Draft/correction creation is timed. No-op calls the actual store unchanged.
  Saved graphs/counts and exact `.previous` bytes are checked outside timing.
- Encoding uses production `.prettyPrinted`/`.sortedKeys`. Atomic JSON+previous
  measures two atomic writes of pre-encoded bytes, without encode, external-change
  guards or validation; it does not test crash durability/fsync.

**Milliseconds: median / p95** at n=100, median only otherwise. The console also
prints min/max for every operation. Three/ten samples do not support reported p95.

| Operation | n per size | 100 points | 1,000 points | 5,000 points |
| --- | ---: | ---: | ---: | ---: |
| read+decode | 10 | 16.774 | 163.668 | 797.498 |
| decode | 10 | 16.521 | 158.340 | 788.875 |
| cold-store-load | 3 | 64.857 | 4595.291 | 112062.308 |
| validate-full | 3 | 45.309 | 4380.551 | 109150.615 |
| validate-base-graph | 3 | 4.037 | 42.251 | 211.456 |
| validate-revisions | 3 | 41.562 | 4309.777 | 108427.922 |
| effective-all | 100 | 0.052 / 0.067 | 1.689 / 2.439 | 4.297 / 6.447 |
| effective-single-last | 100 | 0.033 / 0.057 | 0.377 / 0.497 | 2.285 / 2.862 |
| query-project-sort | 100 | 0.066 / 0.092 | 0.918 / 2.658 | 7.718 / 10.314 |
| effective+query-filter | 100 | 1.995 / 2.736 | 21.219 / 24.635 | 87.237 / 92.326 |
| append-only-membership | 3 | 3.394 | 328.193 | 9450.696 |
| encode | 10 | 17.170 | 180.685 | 880.745 |
| atomic-json+previous | 100 | 5.492 / 7.309 | 17.614 / 20.531 | 36.655 / 68.583 |
| save-no-op | 3 | 109.369 | 5306.383 | 123867.021 |
| save-new | 3 | 108.373 | 5310.884 | 125345.619 |
| save-revision | 3 | 177.004 | 10164.573 | 240962.277 |
| switch-context | 3 | 110.394 | 5387.019 | 126425.923 |

At 5,000 points, full validation ranged 108929.503–109702.131 ms, new saves
124832.961–125408.285 ms and revision saves 239569.688–241350.611 ms (three samples).
Darwin `getrusage(RUSAGE_SELF).ru_maxrss` cumulative process peaks through each size
were **43,958,272 / 307,347,456 / 3,354,464,256 bytes** (41.9 / 293.1 / 3199.1 MiB).
These include XCTest, fixture setup/checks and earlier cases; they do not isolate
per-operation allocations or represent production-app peak memory. Main-actor
elapsed times show synchronous actor occupancy, not physical-device frame drops.

## Three bottlenecks and #34 priorities

N = original points, M = original measurements, R = point revisions, J = joint
sets, F = photos/attachments, B = encoded bytes. This profile has M=2N, R=0.1N,
J=0.5N and F=0.1N. Complexity estimates below come from source inspection.

1. **Repeated whole-graph revision validation: highest benefit, high integrity risk.**
   `MappingJournal.validateRevisions()` replaces the observations array and invokes
   `validateGraph(includingRevisions: false)` for every revision, with a linear
   original lookup too: roughly O(R × (N+M+J)). At 5,000 points it takes **108427.922
   ms**, versus **211.456 ms** for one base-graph pass; full validation takes
   **109150.615 ms**, growing **24.9×** for 5× more points than the 1,000 case.
   `MappingWorkflow.saveCorrection()` and `FileMappingStore.save()` both validate:
   revision saves take **240962.277 ms**, new saves **125345.619 ms**. Build UUID/
   context/ownership indexes once, validate the base once, then each snapshot/chain
   against that context; target O(N+M+J+R × snapshot-size). Consolidate duplicate
   validation only with equivalent failure behavior. #34's equivalence/adversarial
   tests must prove all current checks, ownership and history guarantees remain.
2. **Append-only linear membership scans: next benefit, low–medium risk.**
   `FileMappingStore.save()` uses `previous.*.allSatisfy { journal.*.contains(...) }`;
   expected O(N²+M²+R²+F²), plus value equality. The lookup-shape diagnostic grows
   **3.394 → 328.193 → 9450.696 ms**. Build unique UUID→record maps and compare
   **complete prior values**, targeting linear indexing plus payload comparison.
   UUID identity alone must never permit changed or removed evidence/history.
   Use actual save rows for end-to-end impact; do not subtract this microbenchmark.
3. **Whole-journal JSON work: smaller benefit, medium cache/memory risk.**
   `FileMappingStore.save()` decodes previous bytes, encodes all next records and
   decodes the result for equality: two decodes plus encode per loaded-store commit.
   At 5,000 points, decode is **788.875 ms**, encode **880.745 ms**, read+decode
   **797.498 ms** for 27,769,912 bytes. Traversal is roughly O(B), with object-key
   sorting during encode. Reuse the validated previous journal alongside exact
   loaded bytes, publishing both only after success, to remove one previous-file
   decode. Preserve the encoded round-trip check, external-change guards, atomic
   writes, exact `.previous`, sorted/pretty JSON and schema refusal. Component
   medians are not an exact additive decomposition of save latency.

Bulk effective resolution is already O(N+R): **4.297 / 6.447 ms** at 5,000 points;
combined filtering is **87.237 / 92.326 ms**. Single lookup is O(N+R); reuse validation
indexes where useful before adding dedicated query caches. Sorting generally costs
O(K log K) for K matches, but this fixture is already ordered. Raw atomic writes
are **36.655 / 68.583 ms**. These secondary costs are much smaller than validation.

## Validation and limits

One focused Release benchmark run passed; no additional benchmark run, full SwiftPM
or Xcode regression, DXF audits, stress/fuzz/property tests or independent reviewers.
The initial launch failed before compilation/measurement because the default Clang
cache was outside the writable sandbox; the recorded command redirected caches.
Xcode generation added only this test to the unit-test inventory. Application
compilation is unaffected, so no Simulator build was run. Debug comparison and
physical iPhone/UI profiling were deliberately skipped. No production behavior,
engineering calculations, schema, migration, UI, persistence semantics or user data
were changed. The independent original-measurement journal remains untouched.
