# Complete offline backup and verified restore — format 1

B1a creates and independently reads/verifies a portable backup. B1b adds the
[verified restore protocol](#b1b-verified-restore) below. Issue #23 remains open for review.
Excel collaboration (#68) is a separate exchange workflow; XLSX is not authoritative
backup data.

## Scope and ZIP structure

Settings → «Резервное копирование» → «Создать резервную копию» captures **all projects**,
without period/context filters. The three primary modules stay unchanged.
The output filename is `FieldForge-Backup-YYYY-MM-DD-HHMM.zip` (UTC).

```text
manifest.json
mapping/current.json
mapping/recovery/<original-journal-filename>.<recovery-suffix>
measurements/current.json                             # absent only if never created
measurements/recovery/<original-journal-filename>.<recovery-suffix>
photos/originals/<attachment-UUID>
photos/operations/<photo-UUID>.json                    # if present
photos/staging/<photo-UUID>                            # if present
plans/originals/<attachment-UUID>.dxf
plans/operations/<plan-UUID>.json                      # if present
photos/<other-existing-durable-relative-path>         # preserved, reported incomplete
plans/<other-existing-durable-relative-path>          # preserved, reported incomplete
```

The package uses the existing streaming `XLSXArchive` ZIP writer: ZIP32 STORE (no
compression), UTF-8 names, CRC-32, signed data descriptors and a central directory,
following PKWARE APPNOTE 6.3.10. There is no enclosing directory. Format 1 deliberately
accepts only this writer's profile, including matching local headers/descriptors and
central entries; re-zipping with arbitrary tools may produce an unsupported profile.
The JSON files and originals themselves remain independently inspectable.

`mapping/current.json` is the **exact committed schema-8 JSON bytes**, including
projects, horizons, multi-horizon excavations, plans and their management/revision
relationships, original observations/measurements, all J1–J5 interpretations,
geological descriptions/classifications, stored Barton Q/RMR/GSI data, tectonic
structures, coordinate metadata/provenance, all observation and photo-metadata
revisions, UUIDs and the stored selection. No effective-only projection, rating
recalculation, numeric rounding or schema change occurs. If a fresh installation
has never written a mapping journal, its empty committed graph is encoded only
inside staging; no live journal is created.

Every existing file under the managed photo and plan roots is copied, including
unreferenced originals, staging, malformed intents and unknown recovery files.
Only `photos/thumbnails/` is omitted: these are disposable derivatives. Existing
journal sibling files whose names begin with the current filename plus `.` are
included verbatim in `recovery/` (including `.previous`, `.phase1-backup` and historical
experimental backups). Recovery filenames locate opaque files, never establish
record identity. Their payloads are not upgraded or assumed to use current schemas.

## Manifest contract

`manifest.json` is UTF-8 JSON with sorted keys, pretty printing and these fields:

| Field | Meaning |
| --- | --- |
| `formatVersion` | Integer `1`; unknown values fail verification. |
| `mappingSchemaVersion` | Integer `8`; unsupported schemas fail before any activation. |
| `applicationVersion` | Optional application marketing version, omitted if unavailable. |
| `createdAtUTC` | ISO 8601 timestamp, fractional seconds and `Z`, after snapshot preparation. |
| `projectCount`, `observationCount` | All projects and original points, independently checked against the graph. |
| `measurementIDs` | Ordered UUID array of independent-journal records; mapping readings are in mapping JSON. |
| `independentJournalPresent` | Whether a live independent-journal file existed in the captured loaded state. |
| `files` | Inventory of **every** ZIP payload except the manifest: `path`, integer `byteCount`, lowercase 64-character `sha256`. Actual captured bytes, even if the source is damaged. |
| `attachments` | Graph-derived register detailed below; missing originals retain expected metadata here. |
| `pendingOperationPaths` | Sorted paths of all durable photo/plan operation files, including malformed files. Presence means unresolved. |
| `completenessStatus` | `complete` or `incomplete`, checked against the independently derived report. |
| `report.problems` | Array of `{path, reason}` objects. Empty only for a verified complete package. |

Each `attachments` object has `kind` (`photo`/`dxf`), `recordID` (photo or plan UUID),
`attachmentID`, `projectID`, `path`, expected `byteCount` and expected `sha256`.
Photos also have `pointID` and `pointRevisionID`; original-point context uses the
original point UUID, corrected context uses the exact revision UUID. Optional fields
are omitted rather than fabricated. Legacy plan references without managed bytes
have no expected size/hash and prevent completeness. Horizon/excavation ownership,
plan lineage, original evidence and full metadata remain authoritative in the JSON
graph; the register is re-derived and compared, never used to invent relationships.
Pending intents retain their full versioned UUID relationships and expected original
metadata in their original operation JSON, separate from the committed register.

A file's inventory checksum describes the **captured bytes**. Attachment expectations
come independently from the committed graph. A damaged original can therefore be
preserved while its mismatch is visible. The manifest does not checksum itself;
ZIP CRC checks its transport, and graph/manifest validation checks its meaning.

## Complete, incomplete and failed

A **verified complete** package requires all of the following:

- Supported manifest and schema; authoritative `MappingJournal.validate()` succeeds
  for originals, revisions, geological values, provenance and all graph relationships.
- Exact archive/inventory membership, unique safe paths, matching sizes, SHA-256,
  ZIP CRCs, local headers, descriptors and central-directory bounds.
- Register UUIDs/counts match the graph; each required photo/DXF original matches
  its stored expected byte count and SHA-256.
- Independent journal is included/valid, or explicitly absent because the loaded
  application had no journal file; its IDs match.
- No pending operations, unknown/unreferenced managed files or reported problems.
- Manifest content and completeness/report agree exactly with the captured manifest
  and read-only verification.

An **incomplete** package preserves all readable captured files and reports missing
originals, mismatched originals, independent-journal decoding problems, pending
operations, malformed operation UUIDs and files outside the committed graph. The
screen explicitly says «Не удалось создать полную резервную копию» and offers
«Сохранить неполный архив и отчёт». It never displays the verified-complete badge.
An incomplete archive is useful evidence for reviewed recovery, not a full backup.
The normal UI refuses backup if either application journal could not be opened;
the low-level validator still safely reports independently supplied bad packages.

Unreadable/unsafe sources, I/O failures, concurrent source changes, unsupported
archive structure, cancellation or staging/ZIP limits fail creation. No ZIP is
presented as successfully verified after a verification failure. Only backup-owned
temporary directories are cleaned; source files are never repaired, deleted or reset.

## Consistency and cancellation

`MappingStorageOwner.captureBackup` reserves the existing private FIFO storage
executor for the **entire capture**. It selects its latest committed
`MappingCommittedSnapshot`; drafts and partially buffered commands cannot enter.
`FileMappingStore.backupBytes` checks its loaded bytes and graph against the live
file without reload/adoption or changes to its existing save guards. Pending queued
mapping/photo/DXF commands run before or after this block, never during it.

The independent original-measurement store keeps its deployed format, migrations,
backups, validation and sorting behavior. A recursive file-access lock only excludes
its synchronous load/save operations during capture; recursive acquisition preserves
save's existing load call. MainActor admission disables independent save/delete
while backup is active, so ordinary UI writes do not block waiting on the lock.
Its expected loaded bytes are passed by value and compared before/after capture.
No independent migration is invoked by backup.

Capture inventories sources, copies/hashes each file using 256 KiB chunks into a new
UUID staging directory, re-enumerates the full source set and **re-hashes every source**.
Size, modification time and file identity are compared around each stream. Mapping
and independent loaded bytes are checked again; staged mapping must decode to the
selected committed graph. Additions, deletions, ordinary same-size changes and atomic
replacements cause refusal. Symlinks and nonregular source files are refused. Internal
writers are coordinated; arbitrary external filesystem actors are not locked, so
this is not a filesystem-wide instantaneous snapshot or protection against an active
adversary arranging undetectable change-and-revert races. A returned complete package
still has one valid committed graph and originals matching that graph.

Compression/ZIP writing, hashing and read-only validation run off MainActor. Original
photographs are streamed individually, not accumulated in memory. Journals and JSON
metadata are decoded in memory, matching existing storage architecture. A synchronized
cancellation token bridges task cancellation to the non-suspending FIFO block and
checks every chunk and phase. Cancellation does not roll back or cancel other storage
commands and never touches source data. Once capture is done, the FIFO queue is
released; later commits do not alter staged data. The ZIP remains owned by the screen
and native share controller until sharing finishes; leaving the screen/new creation
cleans that output. Interrupted-process temporary files are in the OS temporary
area and are reclaimable; automatic cleanup never traverses the live data roots.

## Verification and independent measurement coverage

`BackupValidator.verify` is reusable and read-only. It opens the ZIP directly without
extraction and returns `BackupValidation(manifest, report)`; structural errors produce
a noncomplete report with no trusted manifest, and cancellation propagates separately.
It checks entry ranges and duplicate/unsafe names (absolute paths, `..`, `.`, empty
components, backslashes, colon/control characters), rejects unsupported ZIP methods,
links/attributes/encryption/multipart/ZIP64, recalculates CRC/SHA-256, validates the
authoritative graph and re-derives inventory references, counts, pending state and
completeness. Archive file identity/size/modification time are checked before/after
verification. CRC is a ZIP transport check; SHA-256 is the payload integrity check
(NIST FIPS 180-4 algorithm via CryptoKit, with published empty/`abc` test vectors).

The independent journal is **not** mapping's `measurements` table. Its exact
`measurements-v1.json` bytes are stored in `measurements/current.json`; sibling backup
files are also included. `FileMeasurementStore.inspectBackup` decodes deployed schema
1 or 2 and validates savability/unique UUIDs **without** migration or file writes.
Schema 1's migrated values exist only in validator memory. Unsupported/corrupt journals
are preserved in low-level incomplete packages; they cannot earn complete status.
An absent journal is explicit, and deletion/change of a previously loaded journal
fails capture. Existing independent compatibility tests remain required.

## Desktop inspection and security

Use a ZIP viewer to inspect `manifest.json`, `mapping/current.json` and
`measurements/current.json`. Extract only in a new empty directory after checking
paths; never unpack over an application sandbox. With a trusted copy, a small Python
script can independently check inventory bytes without writing anything:

```python
import hashlib, json, zipfile
with zipfile.ZipFile("FieldForge-Backup-YYYY-MM-DD-HHMM.zip") as archive:
    names = archive.namelist()
    assert len(names) == len(set(names))
    manifest = json.loads(archive.read("manifest.json"))
    assert manifest["formatVersion"] == 1
    assert set(names) == {"manifest.json", *(f["path"] for f in manifest["files"])}
    for f in manifest["files"]:
        size, digest = 0, hashlib.sha256()
        with archive.open(f["path"]) as stream:
            while chunk := stream.read(256 * 1024):
                size += len(chunk)
                digest.update(chunk)
        assert size == f["byteCount"]
        assert digest.hexdigest() == f["sha256"]
    print(manifest["completenessStatus"], manifest["report"])
```

This independent checksum example does not substitute for FieldForge's schema/graph
validator, authenticate the sender or claim restore compatibility. UUIDs establish
relationships; filenames/pickets are labels. JSON retains existing numerical precision,
Date wire conventions, units, north/CRS/axes and source provenance. No transformations
or engineering calculations occur.

The archive is **unencrypted**, unsigned and unauthenticated. SHA-256 detects accidental
corruption against the included inventory; someone who replaces both payloads and
manifest can produce a different internally consistent package. Original photographs
retain embedded EXIF/GPS/location and other private metadata byte-for-byte. No EXIF
inference is used to survey underground points, and no sanitization, re-encoding or
thumbnail substitution is performed. Native Files/share destinations may have their
own storage/privacy policies. Keep archives in owner-controlled protected storage.

## Limits and B1b

V1 uses the existing ZIP32 infrastructure: individual files/total archive must fit
below 4 GiB and the entry-count limit; creation reserves overhead and refuses payloads
within 16 MB of the ZIP32 boundary or more than 65,533 inventory files. It does not
truncate or filter an oversized dataset. ZIP64 is a future explicit format change.
Manifest is bounded to 16 MiB on verification; JSON journals to 256 MiB and operation
metadata to 16 MiB. Sufficient temporary disk for staging plus ZIP is needed. A disk
failure yields an error without modifying sources. These limits are not field-capacity
or physical-device performance qualifications.

The original B1a delivery deferred activation. B1b implements isolated extraction,
validation before activation, journaled directory activation with retained previous
readable state, startup recovery and reopened photo/plan/history validation below.
Pending-operation recovery remains reviewed external work; such packages cannot restore. Excel import (#68),
cloud synchronization, SQLite and experimental mapping migrations remain separate.

## Focused verification

Final focused SwiftPM run: **28 tests passed, zero failures** (15 backup tests and
13 existing independent-journal migration tests), with no source concurrency warnings.
Initial failing attempts were used to repair fixture preparation, a file-URL comparison
in inventory and compiler/test-concurrency diagnostics; an additional focused test
protects the captured manifest against staging-file replacement; no full regression was run.
The final incremental generic iOS Simulator Debug build succeeded for arm64/x86_64
with Complete Strict Concurrency Checking and signing disabled. The environment logged
CoreSimulator runtime/service discovery errors, so this verifies compilation, not
launch/share behavior; the unrelated AppIntents metadata notice also remains.
Project generation was byte-for-byte deterministic on two consecutive runs.

```sh
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/fieldforge-a5-module-cache \
CLANG_MODULE_CACHE_PATH=/tmp/fieldforge-a5-clang-cache \
swift test --disable-sandbox --filter 'OfflineBackupTests|MigrationTests'

xcodebuild -project FieldForge.xcodeproj -scheme FieldForge -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/fieldforge-a5-derived CODE_SIGNING_ALLOWED=NO build
```

Local logs (not committed): `/tmp/fieldforge-b1a-focused.log` and
`/tmp/fieldforge-b1a-simulator.log`. `OfflineBackupTests` covers two projects, mixed originals,
J1–J5, Q/RMR/GSI storage, tectonics, corrections/photo-history, actual original-image
bytes with EXIF/GPS, original DXFs, recovery files, SHA vectors, full inventory,
missing/corrupt/truncated inputs, metadata/UUID/staging-manifest tampering, unsafe/duplicate ZIP paths,
cancellation cleanup, same-size external changes/additions, FIFO mapping capture,
independent concurrent writers, fresh absence, legacy decoding and read-only ZIP
validation. Fixtures use isolated temporary directories only. Existing `MigrationTests`
cover deployed independent-journal behavior. Full regression, broad UI automation,
benchmarks and physical device/share qualification are deliberately outside B1a's
focused verification budget.

## B1b verified restore

Format **1**, mapping schema **8** only. Settings → «Резервное копирование» →
«Восстановить из резервной копии» opens the native Files picker for ZIP. The security
scope surrounds a bounded copy into a UUID-owned temporary directory; no parser or
activation operation uses the provider URL. Work runs off MainActor. The preview
shows UTC creation time, both versions, all-project/original-observation/independent
measurement/photo/DXF counts, archive bytes and verification status. An explicit
second confirmation authorizes complete replacement and closing unsaved editors and
drafts. There is no merge, selective import, UUID regeneration or Excel synchronization.

`OfflineRestore.prepare` reuses `BackupValidator` and `BackupArchiveReader`; it adds
no ZIP parser. Both the independently derived report and manifest must be complete.
Incomplete B1a recovery evidence is never eligible. Unsupported/truncated/unsafe ZIPs,
invalid UUIDs, missing or damaged originals, unresolved operations, staging/orphan files
and unknown managed files fail before activation. B1a ZIP32/entry/manifest/journal
limits remain. B1b additionally refuses DXF originals over 32 MiB and photographs over
128 MiB to bound the existing in-memory decoders; no bytes are truncated. Preview reserves three archive sizes plus 32 MiB; activation reserves
three current inventory sizes plus two incoming archive sizes plus 32 MiB. Capacity
checks are conservative admission checks; later disk-full/I/O errors also fail safely.

Extraction streams 256 KiB chunks through the existing CRC-checking reader into a
new private package directory. It preserves exact JSON, photo/EXIF/GPS and DXF bytes.
After extraction, and again at activation, verification compares the full file set,
manifest, sizes, SHA-256, authoritative schema-8 graph, counts, attachment register and
independent IDs. ImageIO checks original image structure/dimensions; the existing DXF
parser checks each original. Cancellation checks run while copying/extracting/hashing
and remove only that preview directory. Activation is deliberately noncancellable
once confirmation has been accepted; closing a screen cannot abandon the transaction.

### Current-data protection and unreadable-data policy

The production roots inspected in B1a all live under Application Support/FieldForge:
`mapping-v1.json`, `measurements-v1.json`, `photos/`, `plans/`, sibling recovery files
and other storage metadata. B1b relies on that common parent on the same filesystem;
it refuses mismatched journal paths rather than partially activating separate roots.
UI-test namespace journals are not restore targets.

Under the existing mapping FIFO reservation and independent recursive file-access
lock, the owner checks its latest committed mapping bytes and expected independent
bytes. It captures/packages/verifies a B1a **complete** protection ZIP. The ZIP and
candidate files are synchronized before an activation intent is written. The entire
old directory is later retained by rename, including thumbnails, unknown top-level
metadata and every previous recovery/operation file. Nothing in it is overwritten.
Protection requires a readable complete current backup: pending operations, damaged
originals, corrupt/unsupported journals or unreliable protection refuse replacement.
There is **no bypass** for an unreadable database. All bytes remain in place for
reviewed external recovery; B1b does not repair/reset the database. A never-written,
empty installation is valid and receives a protected empty dataset.

### Durable activation protocol

The sibling `Application Support/FieldForge-Restore/` is outside the replaceable root:

```text
active.json                       # bounded version-1 activation intent
<transaction UUID>/pre-restore.zip # independently verified B1a protection package
<transaction UUID>/incoming/       # new installed layout before rename
<transaction UUID>/previous/       # exact old root after rename, retained on success
<transaction UUID>/rejected/       # displaced incoming data if rollback was needed
```

1. Validate source ZIP and extracted package again. Reserve the mapping FIFO for
   installation. Permanently retire that owner; queued and later commands
   from old views are rejected. Block AppModel writes and invalidate other loaded
   independent-store write epochs under its file lock.
2. Secure and verify `pre-restore.zip`. Build the installed candidate privately;
   validate its complete file set and reopen semantics. Synchronize files and
   directories, including existing data. No live replacement has happened.
3. Atomically write/synchronize `active.json` with version, transaction UUID,
   original root inode, expected source-manifest SHA-256 and `committed: false`; synchronize containing directories.
4. Rename `FieldForge` to this transaction's `previous`, synchronize both parents.
5. Rename `incoming` to `FieldForge`, synchronize both parents.
6. Revalidate every installed byte/reference and trial-open mapping and independent
   stores without modifying content. Return a `PendingActivation` token; keep
   `active.json` **uncommitted**. File/store success is not application readiness.
7. Construct both actual application models privately. Await mapping initialization,
   check its workflow, error/loading state and attachment stores, and check independent
   model readiness. Independent decoding runs off MainActor. The new mapping FIFO
   rejects generic attachment work and commands while suspended; the independent
   model cannot save. No candidate model or empty fallback is published to views.
8. `RestoreSessionFinalizer` revalidates the installed dataset, then atomically
   persists/synchronizes `committed: true` and removes/synchronizes the active intent.
   Enable candidate writes and publish both models/new navigation generation together
   on MainActor. The progress screen remains until this finishes; only then show
   success. Keep the transaction/protection ZIP and previous root indefinitely.

The two renames are **not** one atomic operation. While busy, application screens
are replaced by a progress screen and no valid dataset is published. `ApplicationSession`
runs recovery off MainActor **before constructing either application store** on
launch and after installation errors. Provisional candidate construction intentionally
skips startup recovery so it cannot accidentally roll back its own pending installation. An uncommitted intent deterministically rolls
back: displace any incoming live root to `rejected`, return `previous` to live. If
`previous` is absent, the live root must have the original recorded inode (either
activation never moved it or rollback already returned it). This makes recovery
idempotent across interruption after either recovery rename. A committed intent is
finished only if its manifest matches the intent's SHA-256 and the complete installed
package still verifies; otherwise rollback
uses the retained old directory. Corrupt intents, missing/ambiguous roots, rename or
sync errors block opening/writes and preserve all files. No missing journal is
interpreted as a fresh empty installation while an unresolved intent exists.

Synchronization failures are errors, not ignored successes. This is a filesystem
crash-recovery protocol, not a claim of protection against broken hardware, a hostile
external filesystem writer or an OS violating its synchronization guarantees.
The old inode is a local recovery identity, never a portable geological record ID.

### Exact evidence, sidecars and model replacement

All UUIDs, original observations, diagnostics/acquisition provenance, J1–J5, geology,
ratings, tectonics, plan relationships, photo/correction history, numeric precision,
wire timestamps/time zones, north references and coordinate metadata stay in exact
original JSON. No engineering recalculation or normalization occurs. Thumbnails can
regenerate independently; they never replace originals.

Incoming `mapping/recovery/*` and `measurements/recovery/*` are stored under
`FieldForge/restored-format-v1/history/<original archive path>`; the exact incoming
manifest is also retained in that marker directory. They are **opaque history**, never
current `.previous` or `.phase1-backup`, and cannot collide with the separate current
transaction's protection copy. Subsequent backups include the marker/history under
`mapping/recovery/restored/`. Repeated restore cycles can nest these history paths;
all existing ZIP32/path limits still apply and excessive history fails explicitly.

A restored independent schema-1 journal is decoded with the deployed compatibility
reader without invoking its migration. The durable `restored-format-v1` marker keeps
loads read-only across launches; the first ordinary user save still writes the
existing schema-2 format. Installations without that marker retain their deployed
migration/backup behavior. Schema-2 restored bytes and an explicitly absent journal
also remain unchanged on load. No original journal or historical sidecar is rewritten
by restoration.

On model-readiness/finalization failure, retire and drain the candidate mapping owner
and disable its independent model **before** filesystem recovery. Persist an
uncommitted rollback decision, move the incoming live root intact to `rejected`,
return the original directory to live, and invalidate all independent loaded-writer
epochs under the file-access lock. This includes writers that loaded the provisional
incoming root. Reopen the original dataset into a new suspended model pair, require
both models usable, then enable/publish it. A rollback or original-model reopening
error removes all accessible models and displays a Russian write-blocked error; it
never falls through to ordinary partial startup or retries the incoming root.

The pending token retains the original intent identity, inode and manifest binding.
It permits a durable rollback decision even if a finalization I/O error occurred after
writing `committed: true` or removing the active pointer, or final publication admission
fails. It verifies the retained original directory identity before reconstructing that
intent. Rollback is idempotent if the original root has already been returned. A crash
before durable finalization (including after model readiness) leaves an uncommitted
intent and rolls back on launch. A crash after durable finalization may retain the
incoming dataset: both model readiness checks have already succeeded. No candidate
writes or UI publication precede that decision.

The old MappingStorageOwner is permanently retired even on failure; its generic
attachment callbacks and durable commands cannot touch the reopened dataset. Old
AppModel saves are disabled, and low-level loaded independent writers are rejected
by a lock-protected write epoch. The replacement models clear drafts, retained
memory-only photo sessions, pending editor requests and active navigation. Disk
recovery evidence is retained; unsaved in-memory drafts are deliberately discarded
only after the replacement confirmation. Disposable active-plan preferences retain
their existing unavailable-selection behavior rather than inventing a plan match.

### B1b limitations and verification

Archives remain unencrypted and unauthenticated; original private EXIF/GPS is retained.
Recovery copies live inside the app sandbox at the disclosed FieldForge-Restore
path; B1b does not provide a recovery-copy browser, pruning or an automatic rollback
button after a committed restore. Keep external backups in Files as well. Current
unreadable/incomplete datasets need reviewed external recovery before this UI can
replace them. Power-loss/device-volume-full qualification and native Files/iCloud
provider testing remain manual-device work. ZIP64, cloud sync, Excel exchange (#68),
selective restore and changes to engineering methods are outside B1b.

Focused tests extend the B1a two-project fixture (original mixed measurements,
J1–J5/geology/Q/RMR/GSI/tectonics/corrections, photo history and EXIF/GPS, DXF), comparing
the full graph and every payload byte after restore. Fault injection covers all six
activation checkpoints and both recovery renames; it also covers corrupt intent,
staging mutation, unsupported/unsafe/corrupt/incomplete sources, capacity refusal,
extraction errors, preactivation cancellation/cleanup, concurrent old mapping and
independent writers, legacy independent bytes/absence and retained protection.
Independent migration tests remain part of the focused run. These tests inject
process interruption at durable boundaries; they do not simulate physical power loss.

B1b executed 36 focused tests (23 backup/restore + 13 independent migration): 35
passed and one unsafe-ZIP fixture failed before reaching restore because the
production writer correctly refused its illegal path. The fixture now mutates safe
ZIP headers; its isolated rerun passed. After the final restore bounds/manifest-binding
changes, **all 8 restore tests passed**. No source concurrency warnings were emitted.
The incremental generic iOS Simulator Debug build succeeded with signing disabled;
CoreSimulator runtime/service errors and the unrelated AppIntents metadata notice are
environment limitations, not launch/device verification. Full regression, broad UI
automation, benchmarks and physical iPhone qualification were deliberately skipped.
Local logs: `/tmp/fieldforge-b1b-focused.log`, `/tmp/fieldforge-b1b-repair.log`,
`/tmp/fieldforge-b1b-restore-final.log`, `/tmp/fieldforge-b1b-simulator.log`.

### Post-activation model-readiness audit (2026-10-24)

The original implementation had a confirmed ordering gap: `activate` trial-opened
low-level stores, wrote committed=true and removed active.json before
`ApplicationSession.reopen` constructed the actual models. A mapping or independent
model error then caused another ordinary reopen, with no pending transaction left to
roll back. A low-level valid incoming dataset could remain installed without a usable
application session. The lifecycle trace established this before the correction;
new deterministic readiness-failure injections exercise that exact post-install window.

Installation and application finalization are now separate phases of the **same**
version-1 intent protocol. No schema, backup format, sensor/engineering calculation,
measurement compatibility, or second persistence system is introduced. The exact
success boundary is: installed bytes and trial stores validated, both real models
ready, durable finalization completed, both models enabled/published while the UI is
still guarded, then the guard is released. `OfflineRestore` remains independent of
SwiftUI; the MainActor finalizer accepts application callbacks and is shared with
fault-injection tests. Readiness errors preserve the incoming installed layout under
`rejected`, the original directory (returned to live) and exact `pre-restore.zip` bytes.

One focused run: **13 restore tests passed, 0 failures**, including five new regression
tests. Cases include independent/mapping model-readiness failure after successful
file/store opens, failure before commit, termination after readiness before commit,
finalization failure after committed=true, publication admission failure after pointer
removal, both interrupted rollback renames, repeated automatic/explicit recovery,
original and protection-byte preservation, stale old/candidate mapping and independent
writers, and success only after readiness/finalization. Model-readiness faults are
injected at the shared application coordinator boundary after real store loads;
these host tests do not instantiate the iOS sensor-backed AppModel or render SwiftUI.

One incremental generic iOS Simulator Debug build **succeeded** with signing disabled.
No source concurrency warnings; the existing SwiftPM cache, CoreSimulator runtime
and unrelated AppIntents metadata notices remain. Full regression, UI automation,
physical-device tests and repeated clean builds were deliberately not run. No failed
command reruns were needed. Logs: `/tmp/fieldforge-b1b-postactivation-tests.log` and
`/tmp/fieldforge-b1b-postactivation-simulator.log`. Filesystem/hardware and provider
limitations described above remain; there is no guarantee against an OS/volume that
violates synchronization semantics. A rollback that cannot persist its decision or
complete its renames blocks access and retains all bytes for subsequent recovery.
