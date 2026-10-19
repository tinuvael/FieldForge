# P4.2 — photographs in a new observation draft

Issue #22, part of #9. The main Russian mapping form accepts camera, multiple Photos and multiple Files images before the first point save. It reuses the P4.1 system adapters, exact received-byte metadata, UUID paths, hash verification, managed staging and saved gallery. No plan or known coordinates are required. There is no preliminary point save, synthetic point, geological correction or separate photo journal.

## Ownership and location contract

`MappingDraft.id` is allocated when the draft starts and becomes the saved observation UUID. `DraftPhotoSession` freezes that UUID and Project/Horizon/Excavation before camera permission or picker presentation. The draft tracks open session UUIDs until cancellation or the entire selected batch finishes. The shared model checks session/context before and after asynchronous image validation. Late callbacks from an ended/discarded/saved draft cannot append to it or the next draft. Returning from a plan or changing tabs keeps the draft.

Current mapping schema **8**, explicitly approved by the owner for this change, adds required `PhotoContext.locationBasis`:

- `pointRevision`: P4.1 photos added to a saved point retain exact historical point revision/location semantics.
- `unknownBeforeFirstSave`: draft photos reference the future original point UUID (version 1), with **unknown capture location**. The frozen project, horizon and excavation remain meaningful. Eventual XY, Z, picket or source plan is not capture-location evidence. This stays unknown even if coordinates were entered before selection, subsequently changed or corrected after save. The saved card distinguishes the linked point from capture location.

This adds no duplicate coordinate snapshot or inferred underground positioning. EXIF/GPS never supplies mine coordinates. EXIF wall time/offset and representation follow P4.1; unknown capture time is never replaced by import time. New photo operation intents are version **2**, requiring the same location contract. Old/malformed intents remain on disk and report a recovery error; no conversion or deletion is attempted.

Only schema 8 is accepted. Schemas 1–7 and unknown/corrupt files fail closed, block writes and preserve the database, `.previous`, historical backups, originals, staging and DXF. Schema 7 is not reused; there is no mapping migration, reset or cleanup. The independent deployed measurement journal and compatibility are unchanged. Current-format append-only evidence, full graph validation, atomic writes and external-change guards remain.

## Save, retry and reset

Accepted draft operations retain exact received bytes in `MappingModel.retainedPhotos`, including camera-only UIImage/JPEG input with no external file. Until Save, bytes are **volatile memory**, not a durable backup. Multiple accepted images remain in memory together; each input has P4.1's 100 MB limit. Bounded, orientation-correct thumbnails/previews do not change received bytes. Removing a draft photo releases volatile ownership; it never deletes files.

The bottom **Сохранить наблюдение** action is disabled while a picker/session, provider batch or other photo operation is active. The service also refuses Save during a live session. Cancellation closes the session without creating a photo. Individual provider/image failures are reported; successfully received images remain in the draft. Save cannot announce completion while the provider batch can still append an image.

Save validates point fields, locks the draft, and for each accepted operation writes the same UUID intent before staging bytes, promotes and independently verifies the original by size/SHA-256, and only then releases the volatile fallback. It publishes point, original measurements, photos and attachment relationships in **one validated atomic mapping-journal commit**. The model checks the frozen draft across disk awaits. Context and plan-point changes are refused while saving.

Validation, intent, staging, promotion or journal failure preserves all fields and operation UUIDs. Ordinary bottom Save retries with retained camera bytes or the verified original; no second shutter or nonexistent file selection is needed. A queued Save for an already committed draft UUID cannot save a second point. After commit, thumbnail/intent-finalization failure is a warning on an already saved observation, retryable through the saved card without duplication.

Success retains Project/Horizon/Excavation, starts a fresh draft UUID and suggests nominal horizon Z again. Picket/interval, XY, source plan/provenance, measurements, geology/interpretations, ratings, tectonics, notes, date/time-zone override and photos clear. Original observation/measurement evidence, P3.3 and photo histories remain append-only. Reconstructed correction forms use the saved observation UUID to preserve existing baseline-integrity checks.

## Discard and unfinished files

Photos alone, or an active picker, make the draft dirty. Context changes require **Удалить черновик / Остаться**. Cancel preserves everything. Successful discard releases memory ownership, invalidates old sessions and starts a fresh draft. A failed context commit keeps the old draft intact.

Files are never automatically deleted on removal/discard. A failed Save can leave intents, staging or promoted originals. These remain visible as unfinished draft-file status and belong in a complete offline backup. They never attach to a new draft or publish a synthetic point. `retryPhoto` refuses to publish a draft intent without its already committed exact photo pair. Saved originals are unaffected.

This stage does **not** autosave or recover the unsaved form after process termination. Unwritten camera bytes are lost at termination. If image bytes reached disk but the point commit failed, files/intents survive, but the missing form cannot be reconstructed or automatically committed. Preserve the directory for reviewed recovery. A successful journal commit reopens its complete point/photo graph normally. Malformed intents report an error and remain preserved.

The complete backup composition and privacy limits in [P4.1](p4-1-photos.md) still apply. No package exporter, point-free photos, viewing direction, saved-original deletion, LiDAR or wedge calculation is added. See [verification](p4-2-verification.md) for actual executions and separate real-camera/provider limits.
