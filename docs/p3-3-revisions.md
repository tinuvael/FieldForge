# P3.3 — immutable saved observation corrections

Issue: https://github.com/tinuvael/FieldForge/issues/19. This extends the existing schema-5 mapping aggregate; there is no separate journal, database engine, dependency or measurement algorithm.

## Identity and time

`MappingJournal.observations` retains immutable original `MappingObservation` values. An original is version 1 and has no synthetic revision UUID. `MappingObservationRevision` stores:

| Field | Contract |
| --- | --- |
| `id` | Unique correction UUID |
| `observationID` | Stable original point UUID |
| `version` | Consecutive integer, first correction 2 |
| `previousRevisionID` | Nil for version 2; exact previous correction UUID thereafter |
| `correctedAt` | Exact Foundation `Date` instant, captured on successful save attempt; no rounding |
| `author` | Optional manually supplied text; no fabricated user identity |
| `reason` | Required non-whitespace correction explanation |
| `snapshot` | Complete validated corrected observation, retaining original point identity/ownership |

Field date/time, zone ID and recorded UTC offset remain in each snapshot and are separate from correction time. A correction that leaves date/zone unchanged retains the original exact instant and historic UTC offset, independent of current time-zone rules. Editing date/zone explicitly derives the new offset from the selected IANA zone. Creation timestamps remain original; correction timestamps belong exclusively to revision records. JSON dates retain the existing seconds-since-2001 encoding and full floating-point precision.

`effectiveObservation` / `effectiveObservations` project one current snapshot per original UUID. History array order is validated, rather than trusting timestamps or sorting a damaged chain. Journal date/picket filters, details and DXF markers read this projection; historical navigation uses a frozen snapshot and disables editing. Comparison lists changed fields with links to complete before/after detail screens.

## Editing boundary

`MappingCorrectionDraft` freezes the effective baseline, predecessor and complete original evidence. `MappingDraft` is prefilled with field text, exact numeric values and frozen coordinate provenance. Its separate state does not touch a pending new-observation draft or project selection. The UI permits picket/chainage origin, field date/zone, manual X/Y/Z and coordinate provenance, optional interval/position, notes, J1–J5 interpretations and descriptions, full/partial/unknown tectonic orientations, thickness/position/description, and existing Q/RMR inputs.

Project, horizon and excavation IDs cannot change. Source measurement arrays and ownership must remain exactly equal to the original. There is no correction-time capture, removal, mutation or reassignment of raw readings. Interpreted evidence links can cite only originals already owned by this point; history retains previous links. Geological IDs may recur only within the same point/kind; joint identifiers remain explicit J1–J5 interpretations. Unchanged joint snapshots retain timestamps and local revision; changed sets retain identity and increment local revision with the correction instant. Added interpretations start at local revision 1. A joint UUID cannot be reused after withdrawal with contradictory local-version content; validation compares its last seen snapshot across the entire history. Re-adding through the UI creates a new UUID. Removal affects only the new snapshot; historical geology remains.

Unchanged Q and RMR assessments retain their exact prior method/input/result/timestamp snapshots. Changed Q inputs call the existing frozen `NGI-Q-2025-04/FieldForge-1` evaluator (see [published reference and independent engineering cases](p3-2b-ratings.md)); no coefficients/tables change. Changed RMR89 inputs remain uncalculated.

## Coordinates and DXF

The correction picker lists saved immutable plans of the original horizon, independent of the currently selected capture horizon. Confirmed XY goes only to the correction draft through the existing `selectPlanPoint` adapter. It freezes plan UUID, revision, file hash, confirmed drawing units, CRS/axes and explicit user-selected provenance. No new CRS or north conversion is introduced. Manual XY edits in a selected drawing switch source to `manualInPlan` while retaining its exact frame/version. The plan frame metadata is read-only in that editor; correcting a frame requires selecting a separately imported correct plan version. Z is always meters, independent of drawing XY units; manual override/clear removes the old horizon-default provenance. Unchanged legacy coordinates/provenance remain exact and no current horizon elevation is silently reapplied.

Normal plan navigation retains existing project/horizon selection isolation. The correction picker explicitly scopes overlays to its frozen saved plan, allowing a point opened from an all-horizon journal to use its own plan. All overlays derive one latest snapshot per point. Moving to another saved version removes the marker from the previous plan; both locations stay in history. No DXF parsing, rendering geometry or original files are changed.

## Atomicity and compatibility

Schema 6 adds one required `revisions` table. Existing schemas 1–5 receive an empty array only after validating the existing graph, encoding/decoding an equal upgraded graph, preserving exact original bytes in a non-overwriting `.pN-backup` and rechecking source bytes. Schema 5 uses `.p5-backup`. A nonempty revision table under an old schema header is rejected before any migration/backup write; history is never silently discarded because a header was damaged. Backup conflict/I/O failure, corrupt or unsupported schema and missing current revision/evidence tables block writes without reset. The active path and all bundle/signing identifiers stay unchanged.

`saveCorrection` rejects stale baselines/predecessors, invalid fields, missing reason, evidence changes, ownership changes, broken chains and invalid geology/ratings/plan relationships. It validates the whole proposed graph and commits once. `FileMappingStore` protects every previously loaded original, measurement, plan and revision against modification/removal; validates round-trip equality; writes `.previous`; rechecks loaded bytes; then atomically replaces the active file. Published workflow state changes only after save succeeds. Error leaves the entire correction draft editable and retryable. The editor disables swipe dismissal while dirty and asks before Cancel discards changes.

Storage remains a single-process, whole-file Foundation atomic replacement, not a multi-process transactional database or cryptographically authenticated audit log. No physical power-loss/storage-full durability claim is made. Full snapshots intentionally trade disk space for a small, reviewable schema extension; large-history performance is not qualified. Drafts stay in memory; process termination recovery/autosave is out of scope. Old application versions cannot open schema 6; migration backups are recovery evidence, not an automatic downgrade. Complete offline backups still need JSON plus managed original DXF files, not JSON alone.

## Verification

See [P3.3 test report](p3-3-verification.md). Core regression tests retain existing published-method checks, original measurement validation, real DXF fixtures and legacy migrations. New tests cover corrections, evidence invariance, chain integrity, exact migration backups, errors/retry and disk reopen. Simulator tests exercise normal capture, editor prefill, dirty Cancel, required reason, J1/fault changes, DXF movement, history/comparison, sequential revisions and relaunch.
