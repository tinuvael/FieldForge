# Complete offline backup — format 1 (B1a)

B1a creates and independently reads/verifies a portable backup. It does **not**
restore, activate, migrate, merge or import data. Issue #23 remains open for B1b.
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

B1b must add extraction into isolated staging, reviewed pending-operation recovery,
validation before activation, atomic activation/journal-and-original relationships,
retained previous readable state, interrupted-activation recovery and verified relaunch
photo/plan/history behavior. It must preserve independent-journal compatibility and
the schema-8/no-reset policy. No Restore button is shipped by B1a. Excel import (#68),
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
