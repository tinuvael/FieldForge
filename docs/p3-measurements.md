# P3.1 integrated orientation measurements

## Capture and ownership

Mapping exposes «Измерить iPhone» and «Ручной ввод». Both append original `Measurement` values to `MappingDraft.measurements`, with stable UUIDs and independent capture timestamps. A draft supports any mixture of validated manual and automatic originals. Removing an original from an unsaved draft changes no persisted evidence. These are not J1–J5 interpretations.

The automatic sheet shares the application's single `MeasurementAcquisition`, provider and `MeasurementSession` with the independent measurement workflow. It uses the unchanged Phase 1 screen-plane calculation, quality gates and full original `SensorSample`; see [geometry conventions and references](measurement-geometry.md). No geological algorithm, north conversion or phone-heading substitution is introduced. The dial is schematic: an ellipse illustrates plane tilt, and the arrow points downhill in the reading's north frame. Undefined azimuth remains absent with its reason, including near-horizontal/vertical and unavailable north cases. Inclination-only originals remain explicitly incomplete. Simulator samples retain their DEMO source/reference.

HOLD accepts only fresh (0–1.5 seconds old), valid, sufficiently stationary samples and freezes the complete original reading. It stops acquisition. Retake clears the held reading and starts fresh acquisition. Hidden/manual/background states stop the same provider and discard unfrozen data; held data survives temporary backgrounding. Late events while stopped are ignored. A visible/live foreground sheet runs the existing 20 Hz provider. Dismissing the sheet adds nothing; «Добавить замер» appends once and closes. Neither mapping capture path calls the standalone measurement store. The standalone manual/automatic journal workflow remains accessible under Services.

## Atomic storage

`MappingJournal` schema 3 adds one original-measurement table. Each `MappingObservation.measurementIDs` array owns its originals, in capture order. Its project/horizon/excavation context is inherited through the owning point's stable UUID relationships. Validation requires every original UUID to exist exactly once and to be owned by exactly one point; all originals must pass the existing source-specific validation. Missing, duplicate, shared, orphaned or tampered originals reject the entire commit. Saved observations, original measurements and plan references remain append-only.

The main «Сохранить наблюдение» builds and validates the complete graph, then atomically writes the point and all its originals in `mapping-v1.json`. Only after successful persistence does the workflow publish/reset. Failure leaves the full draft and previous in-memory graph unchanged. Success keeps Project/Horizon/Excavation and reapplies nominal horizon Z; measurements, picket, XY, selected plan point, notes and date override clear. The next point uses the current observation time. Measurement-only drafts also require confirmation before changing any persistent context.

The `MappingModel` owns the unsaved draft across tabs, plan sheets and temporary backgrounding. No background autosave or completed observation is fabricated. Unsaved drafts are in memory and do not survive process termination; save the point before closing the application. Journal and plan-marker details resolve the same point's originals and open their full manual/raw diagnostic detail view.

## Compatibility and boundaries

The active mapping filename, standalone journal, bundle identifier, signing and managed DXF originals are retained. Existing v1/v2 mapping graphs decode with an empty original table only when absent in the old schema. The existing lossless upgrade mechanism now writes schema 3, preserving the source bytes in `.p1-backup` or `.p2-backup` respectively before atomic replacement. Invalid/unsupported files and conflicting/failed backups block writes; there is no reset, record deletion or DXF rewrite. A schema-3 file missing its evidence table fails closed. Older applications cannot read schema 3; downgrade requires a reviewed recovery plan.

Mapping export, classification, representative sets, faults, photos, and new DXF functionality are outside P3.1. The existing CSV export continues to cover only the independent journal. Physical accuracy has not been validated; mock and simulator tests establish software behavior only. No physical iPhone installation or data access is part of verification.
