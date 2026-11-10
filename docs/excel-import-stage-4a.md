# Stage 4a — import ledger and safe apply

## Existing storage and workbook boundaries

`MappingStorageOwner` already serializes mapping writes, captures a consistent backup generation, and retires before a restore replaces the live root. `FileMappingStore` validates the graph, refuses external file changes, checks append-only evidence and writes the prior bytes to `.previous` before atomically replacing the current file. Controlled field corrections append a `MappingObservationRevision` with the observation UUID, previous revision, version, time, author, reason and exact snapshot. Stage 4a shares the revision append code and uses the same storage owner and file replacement.

An observation is the station/point identity in the current journal. It has one UUID and explicit project, horizon and excavation UUIDs. Picket and numeric chainage describe location. A different observation may have the same picket, coordinates or excavation name.

Exchange v1 exports UUIDs, history and evidence. Its read-only preview validates the workbook, reconstructs its source graph and compares it to a committed snapshot. The regulatory exporter projects effective records to `Data!A:AD`, including multiple tectonic rows where applicable. Its report columns cannot establish observation identity. The existing Exchange preview exposes read-only classifications and field diffs.

Photo records reference the exact original or corrected observation revision. Mapping readings, interpretations (including historical J5), and stored ratings stay in their original records and prior revisions. DXF references, attachments and original bytes keep their existing lifecycle. The independent measurement journal keeps its own storage and deployed compatibility.

## Persistence and conflicts

Schema 8 gains the optional `importLedger` field. Earlier schema-8 files omit it and open without a rewrite. A present field requires ledger format 1, a nonempty entries array and a matching SHA-256 digest. The digest covers canonical sorted-key JSON using the Exchange encoder's reference-epoch date encoding. The ledger stores the following metadata.

- Operation UUID, source type, stable document and row identities, and SHA-256 of the exact reviewed source bytes.
- Observation/project/horizon/excavation UUIDs, operation kind, expected revision ID and number (version 1 has no revision ID), and baseline snapshot digest where applicable.
- Approved proposal digest and frozen creation or correction metadata. Correction metadata records time, reason and optional author. Preview conflicts carry a bounded diagnostic note.
- Pending, applied, skipped or rejected outcome. The observation UUID locates an applied create. The operation UUID is the resulting revision UUID for an applied update.

A row key is scoped to its source type and document identity. An active intent or applied receipt reserves that row and fingerprint. The same row can update the same target after a source version changes and a fresh baseline is confirmed. A different fingerprint cannot rebind the row or create another point. A matching operation UUID and intent return the saved terminal outcome without writing. Reusing an operation UUID with a different intent, or submitting different source/proposal fingerprints, returns a typed input error and keeps any legitimate pending intent intact.

Fresh or resumed mutations check ownership, existence, revision ID and number, and exact snapshot fingerprint. Revision conflicts include the current revision ID and number so the adapter can guide the user to a fresh preview. A same-revision fingerprint conflict requires review of the local evidence. Duplicate diagnostics include the existing operation UUID. A source mismatch requires the reviewed workbook bytes. A proposal mismatch requires reconstructing the same approved values. Invalid proposals require correction and review before a new operation is prepared.

An update retains measurement IDs, exact historical J5 interpretations and the existing ratings snapshot. A create carries no original field measurement IDs or historical J5. The command accepts a fully approved domain snapshot, validates it with the existing graph rules and performs no rating calculations or coordinate transformations. A no-op update records a skip. Source-level skips and preview conflicts can also be recorded without changing the observation. The workbook adapter must verify the proposal came from the reviewed source and that each changed field was authorized.

On load, an applied receipt must resolve to the exact original or historical revision, even after subsequent corrections. An update receipt must also match the predecessor snapshot, revision chain and correction metadata. Missing or malformed present ledger data, a bad checksum or an inconsistent receipt blocks ordinary writes through the existing storage error path and preserves the current file and `.previous`. Normal saves cannot remove or rewrite an intent or terminal receipt. SHA-256 serves as an integrity check.

## Recovery protocol

The current journal is the authority. Each mutation uses two atomic replacements under the same FIFO owner. The first persists the intent alone. The second replaces the current file with the observation change and applied receipt together. The owner publishes each successful persisted generation internally before returning.

| Point of interruption | Current journal on reopen | Recovery |
| --- | --- | --- |
| Before the intent replacement | Previous journal generation | Prepare or resubmit the same approved operation. |
| After intent replacement, before the final replacement | Pending intent. The observation reflects other committed work. | Revalidate against the current graph. If eligible, resupply the exact reviewed source and proposal. If stale, recovery reports the conflict and resubmitting the intent persists a rejection without a revision. |
| During either replacement or its `.previous` write | Last successful current journal, or the newly replaced journal if replacement completed | Inspect current state. An I/O or insufficient-space error can be retried after storage is available. `.previous` is a historical snapshot, and the code never promotes it automatically. |
| After the final replacement, before the caller receives confirmation | Observation change and applied receipt are both present | Return the saved outcome for the identical operation. This also covers interruption during a recovery attempt. |
| Ledger malformed or claims an inconsistent graph | Store refuses the current journal | Preserve the files for review or use the existing reviewed restore path. |

The observation change and receipt become visible in the same current generation. After reopening, `importRecovery()` classifies pending intents without modifying the file. A valid pending intent is unapplied and awaits the approved proposal. A stale pending intent is unapplied and requires review. Recovery requires the approved payload and its source. The ledger retains their digests and the creation or correction metadata. The same owner can continue regular mapping after an interrupted import, and retry checks the latest committed baseline.

Backup format 1 includes the ledger inside `mapping/current.json` and in any captured journal history that contains it. The manifest hashes those bytes through existing coverage. Pending Excel intents have no referenced payload file and do not add a photo/plan `pendingOperationPaths` entry. Restore revalidates the same current journal, and protective backups and rollback retain exact file generations. An intentional restore predating an intent or receipt restores the replay history as of that snapshot. Earlier app builds that rewrite schema 8 may omit fields they do not recognize, so retain a Stage 4a or newer app when working with journals containing import state.

## Stage 4b integration

1. Extend Exchange preview preparation to retain the raw workbook SHA-256 alongside its workbook UUID and semantic proposal digest. At confirmation, reopen/revalidate the workbook through the existing bounded reader and compare both digests. Use the confirmed preview's observation UUID or explicit client record ID, and capture each durable baseline from that preview's committed snapshot.
2. Validate protected workbook relationships and apply its field-level rules. Freeze the final new UUID/time and correction metadata once. Stamp changed joint interpretations using the normal revision/time rules. Reuse the ledger's document/row binding before allocating a new point, and preserve the resolved UUID, operation UUID and timestamps on retry. The adapter must provide any additional per-field authorization and deterministic reconstruction data needed by its proposals. Rating edits need an explicit reviewed policy before enabling them.
3. Route confirmed mutations through the existing FIFO owner. Add batch preflight and two batch saves (intents, then observations plus receipts) if the confirmed user action covers multiple rows as a unit. The Stage 4a command commits one observation at a time. Review stale, ambiguous and unsupported rows before offering confirmation. Prepare the existing verified protective backup if the batch workflow requires it.
4. After a durable result, reconcile the latest committed snapshot into the mapping presentation and report the per-row outcomes. Offer recovery for pending rows and use the persisted receipt if the app closed before displaying success. Keep workbook extraction, confirmation, discard of unresolved intents, and Russian UI diagnostics in the adapter. Stage 4c must define its own explicit UUID crosswalk for regulatory rows.

The implementation covers process interruption and reopen under the existing Foundation atomic file replacement contract. Device power-loss flushing, concurrent independent processes writing the same file, large import batch throughput and a workbook write UI are outside this stage.

## Verification

| Check | Result |
| --- | --- |
| SwiftPM focused tests | 94 distinct cases passed across two runs. Exchange preview (17), regulatory exports (3), offline backup and restore (28), and observation revisions (18) passed in the first run. The ledger (10) and photo (18) tests passed in a focused retry with access to the macOS image type registry, following image-recognition failures in the restricted run. |
| iOS Simulator | Xcode 26.6 `build-for-testing` succeeded for `generic/platform=iOS Simulator` with signing disabled. This compiled the app, unit tests and UI tests. |
| Source inventory | Regenerated the Xcode project and verified the diff with `git diff --check`. |

Verification was scoped to the affected paths. The full SwiftPM and Simulator test suites,
Simulator execution, physical-device recovery and physical power-loss tests were skipped.
