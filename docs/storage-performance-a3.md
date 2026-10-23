# A3 mapping validation and storage performance (#34)

A3 builds on main `6a82550` (A2 PR #63). The production baseline is unchanged
between A2's `ec4b726` and that main commit. Schema 8, JSON fields, calculations,
UI, exports and attachment formats are unchanged.

## Implementation and integrity

- One full validation call checks the base graph once and builds transient context
  dictionaries/sets. Originals and every revision snapshot use the same complete
  observation validator, including ratings, geology, time, location and plan/Z
  provenance. Original UUID lookup is indexed. Existing sequential/predecessor,
  immutable-context/evidence, geological ownership and interpretation-version
  checks still process every revision in stored order.
- Revision validation removes O(R × (N+M+J)) whole-graph substitutions and O(R×N)
  original lookups. It now costs O(N+M+J + total revision snapshot payload), apart
  from unchanged shared plan checks. Full validation calls that indexed revision
  pass with its already checked context. Standalone `validateRevisions()` also
  checks the base graph once when revisions exist.
- Append-only verification replaces O(N²+M²+R²+F²) membership scans with transient
  UUID dictionaries and complete prior-value equality: linear indexing plus
  payload comparisons. It covers originals, measurements, observation corrections,
  photos, attachments and photo metadata corrections. Duplicate IDs are rejected
  before this storage check. Interleaving independent chains/reordering independent
  records remains allowed; changing values under the same UUID is rejected.
- Single effective lookup searches backward without allocating a filtered history.
  Worst-case complexity remains O(N+R). Bulk resolution was already O(N+R), and
  ordered full-history queries remain linear. No persistent caches are introduced.

Authoritative validation still runs on load and save; backup files opened through
the store use that same path. Previous bytes are still decoded on every commit.
Plan/lithology retention, encoded round-trip equality, both external-change guards,
atomic write order, exact `.previous` bytes and failure publication are unchanged.
No incremental acceptance path or new persistence engine is introduced.

## Reproduction and method

```sh
CLANG_MODULE_CACHE_PATH=/tmp/fieldforge-storage-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/fieldforge-storage-swift-cache \
FIELD_FORGE_STORAGE_BENCHMARKS=1 FIELD_FORGE_STORAGE_A3=1 \
swift test --disable-sandbox -c release --filter MappingStorageBenchmarkTests
```

The measured run added `--skip-build` after the targeted Release tests compiled the
final sources. This does not change timed code. A3 mode uses A2's existing test,
exact deterministic fixtures, ascending 100/1,000/5,000 sizes, main actor, timing
helper, three expensive-operation samples and three successive write commits.
Checks, fixture construction and store/workflow initialization remain outside the
timed intervals. It skips unrelated read/decode/load, filtering, encoding, raw I/O,
no-op and context-switch cases; effective queries retain 100 samples. No warm-up
samples were discarded, OS caches were not flushed, and the full baseline was not
rerun. A2 numbers below are recorded historical medians, not a paired same-process
experiment.

The append-only diagnostic now invokes the production indexed helper, including
index construction and photo metadata revisions (empty in these fixtures); A2
replayed five `contains` membership shapes. This measures the replacement check,
not an identical microbenchmark implementation, and still excludes decoding,
plan/lithology retention and I/O. Standalone revision timing now includes one base
pass; full validation reuses its base pass. Component medians are not additive.

Measured 2026-10-23 on macOS 26.6.2 (25G83), x86_64, Intel Core i7-1068NG7 2.30 GHz,
4 physical/8 logical cores, 32 GiB RAM; Xcode 26.6 (17F113), Apple Swift 6.3.3
(`swiftlang-6.3.3.1.3`, `clang-2100.1.1.101`), SwiftPM Release. Hardware/toolchain
match A2. No build/test process ran concurrently with the benchmark. Background
load, thermals and storage media were not controlled.

One limited run, 10:19:46–10:20:30 UTC: **44.151 s, one test, zero failures**.
Fixture JSON byte counts exactly match A2: 559,427 / 5,554,112 / 27,769,912.

**Milliseconds, A2 median → A3 median.** Expensive rows have n=3 per size;
query rows have n=100. Three samples do not support p95 or confidence bounds.

| Operation | 100 points | 1,000 points | 5,000 points |
| --- | ---: | ---: | ---: |
| Full validation | 45.309 → 5.970 | 4380.551 → 68.616 | 109150.615 → 530.230 |
| Base graph | 4.037 → 3.793 | 42.251 → 43.053 | 211.456 → 204.621 |
| Standalone revision validation | 41.562 → 5.313 | 4309.777 → 62.886 | 108427.922 → 285.325 |
| New observation save | 108.373 → 63.323 | 5310.884 → 589.817 | 125345.619 → 3111.823 |
| Revision save | 177.004 → 75.338 | 10164.573 → 654.637 | 240962.277 → 3695.766 |
| Append-only diagnostic | 3.394 → 0.704 | 328.193 → 8.945 | 9450.696 → 48.592 |
| Effective all | 0.052 → 0.046 | 1.689 → 0.919 | 4.297 → 3.614 |
| Effective single last | 0.033 → 0.033 | 0.377 → 0.334 | 2.285 → 2.025 |

At 5,000 points the observed full-validation/new-save/revision-save reductions are
about **206× / 40× / 65×**. Full validation ranged 529.923–532.816 ms, new saves
3106.615–3194.053 ms, revision saves 3688.530–3714.956 ms. Revision validation was
270.902–297.111 ms; append-only verification was 48.185–53.019 ms. Base-graph time
is broadly unchanged (including a small 1,000-point regression); the dominant
benefit comes from eliminating repeated work, not faster geological calculations.
At 5,000 points effective-all p95 was 4.573 ms (A2 6.447), single-last 2.549 ms
(A2 2.862); these small query changes are secondary and sensitive to host noise.
The restricted workload's cumulative process peak was 676,810,752 bytes through
5,000 points; omitted operations make this unsuitable for a direct A2 memory ratio.

## Verification and limits

Targeted command (Release, the same compiler-cache variables as above):

```sh
swift test --disable-sandbox -c release --filter 'MappingValidationPerformanceTests|MappingTests|P33RevisionTests|P41PhotoTests|P42DraftPhotoTests|PlanRevisionManagementTests|P32RatingsTests|MappingJournalQueryTests'
```

The selected Release tests passed: 71 mapping/query/schema/rating/revision/A3 tests
and 39 photo/draft-photo/plan tests, including six new adversarial A3 cases. Tests
cover duplicate table IDs; broken context/evidence/history FKs; invalid historical
snapshots and plan provenance; cross-point/cross-kind geological UUID reuse;
broken/reordered/divergent chains; tampered Q/RMR metadata/results; dangling photo
and attachment links; same-UUID modifications in all six evidence tables; external
file changes; failed backup writes/retry; exact `.previous`; current-schema reopen
and effective observation resolution. Existing measurement migration tests remain
unchanged; the selected mapping tests include legacy journal preservation.

The first compile attempt stopped before tests because the benchmark source was
edited while compilation was active. The completed restricted run passed all 71
non-photo tests, but system image decoding failed in photo tests and the process
later trapped before plan tests. Re-running only the affected photo classes and
unexecuted plan class outside that sandbox passed all 39 without code changes.
One generic iOS Simulator Debug build passed with signing disabled. Xcode project
inventory was regenerated for the new test file.

Full SwiftPM/Xcode regression, Simulator test execution, physical-device profiling,
large DXF fixtures/audits and stress tests were deliberately skipped. The benchmark
contains synthetic metadata references, not image/DXF byte I/O, and has sparse
histories; it does not qualify dense/deep history workloads or device frame rates.

Whole-journal JSON decoding/encoding/round-trip equality and synchronous main-actor
writes remain. Corrections still validate both before workflow commit and inside
the file store. Photo validation still resolves historical points with linear
searches, and plan dependency/compatibility scans remain; full validation as a
whole is not claimed to be linear. Previous-journal caching, asynchronous storage
and a database engine are deferred. No user journals or backup/attachment files
were opened or changed.
