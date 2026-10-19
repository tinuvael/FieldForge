# P4.1 — photographs on saved observations

This implements the first stage of Issue #9. It does not close the parent issue. `MappingObservation.id` is the existing stable point identity; no parallel `SpatialObservationPoint` table, duplicated coordinates or photo journal is introduced. All project data uses the same mapping aggregate. Draft-point and point-free photos, viewing direction, photo deletion, workstation XLSX/ZIP packages and native iPad target work remain later stages.

## User workflow

Open a saved observation from the project journal or an existing DXF marker. The same card offers **Фотографии**: camera, multiple Photos selections and multiple Files imports. Neither a plan nor coordinates are prerequisites. System Photos selection grants access only to selected items; no broad Photos-library permission or background library enumeration is requested. Files uses security-scoped, coordinated reads. Camera checks hardware availability before presentation and handles denied/restricted authorization explicitly; Simulator offers Photos/Files instead. Cancel before receiving an image creates no record.

Each image is a separate operation, including images with identical source filenames. A batch can contain successful and failed *individual* images: each published photo has a complete original/attachment pair; failed individual operations stay recoverable. Loading is sequential, with one image of at most 100 MB in memory at a time. Unsupported/corrupt images are rejected before creating an intent; ImageIO detects actual format and dimensions (up to 100,000 pixels per axis). Animated/multi-image assets preserve received bytes; the first image supplies dimensions and preview. RAW/other platform codecs are accepted only if ImageIO can decode a preview.

A bounded 400-pixel thumbnail gallery opens a metadata card. Tap its preview for full-screen pan/pinch zoom (up to 8× on a 4096-pixel display derivative). Display limits do not reduce originals. Names/numbers, descriptions and categories can be corrected with a required reason; the card retains and displays each previous metadata snapshot. Capture time is read-only evidence. Unknown capture time is never replaced by import time. Timezone-qualified EXIF can establish a capture instant; EXIF wall time without an offset remains original text with an unknown instant. Camera-supplied EXIF time is retained even when UIKit supplies only an image. Without a timezone-qualified capture time, the capture instant stays unknown; callback/import time never substitutes for shutter time.

## Schema 7, identity and evidence

Schema 7 adds only three aggregate arrays:

- `photos: [PhotoObservation]`: stable photo UUID, original attachment UUID, frozen context, source (`camera`, `photos`, `files`), import instant, optional capture instant, original EXIF time text/provenance, initial name/number/description/category.
- `photoAttachments: [PhotoAttachment]`: stable attachment UUID, original filename as metadata, SHA-256, exact received byte count, ImageIO format UTI/MIME type, pixel dimensions/orientation and representation limitation. Paths are derived exclusively from UUIDs.
- `photoRevisions: [PhotoMetadataRevision]`: append-only photo metadata snapshots with own UUID, predecessor, sequential version, correction time and reason. A stale metadata editor cannot overwrite newer metadata.

Every `PhotoContext` freezes project, horizon, excavation, point UUID and exact P3.3 snapshot before requesting camera access/opening the picker. Version 1 references the original point UUID; version 2+ references the exact `MappingObservationRevision.id` and version. That snapshot supplies coordinates, CRS/units/axes, plan version, chainage and provenance. Subsequent selection or location corrections cannot rebind the photo. The card links to both its historical point snapshot and current observation. Current plan markers already open the shared current card and gallery.

Original observations, measurements, P3.3 revisions, plans, photo/attachment originals and photo metadata histories are append-only. Photo additions never call `saveCorrection` or mutate geological arrays. Graph validation rejects dangling, cross-project or mismatched-version contexts, duplicate UUIDs, reused attachments, orphan attachments, broken revision chains, invalid metadata and photos hidden under old schema headers. Missing files do not invalidate/delete domain records.

`FileMappingStore` upgrades schemas 1–6 using the established mechanism: validate source, preserve exact bytes in a non-overwriting `mapping-v1.json.pN-backup` (schema 6 → `.p6-backup`), verify equality/round trip/source unchanged, atomically replace. Existing schema 6 revisions are preserved exactly. A different existing backup, malformed/unknown schema, corrupt graph, changed source or failed write blocks writes and preserves the source; no reset/automatic rollback. Schema 7 requires all three tables, even when empty. Downgrading to schema-6 code requires a separately reviewed recovery procedure.

## Managed files and recovery

Paths relative to Application Support/FieldForge:

```text
mapping-v1.json                         authoritative graph
mapping-v1.json.previous                prior atomic snapshot
mapping-v1.json.pN-backup                exact pre-migration bytes, where present
photos/operations/<photo-uuid>.json      version-1 persisted operation intent
photos/staging/<photo-uuid>              received bytes before promotion
photos/originals/<attachment-uuid>       exact received bytes, format is metadata
photos/thumbnails/<attachment-uuid>.jpg  disposable, orientation-correct, no source EXIF/GPS
plans/                                 existing managed DXF originals/operations
```

1. Validate received image, calculate size/hash and create UUID pair plus frozen context. Atomically persist the complete version-1 operation intent **before** staging bytes.
2. Atomically write staging and verify expected bytes. Promote on the same volume to the immutable original path; an existing original must match expected size/hash and is never overwritten.
3. Read/verify the promoted original, append the photo and attachment together via the validated atomic journal commit, then publish UI state. Journal failure leaves the intent and original without a published partial relationship.
4. Generate the separate thumbnail; only then remove the operation intent. A thumbnail failure leaves the original/photo available and intent retryable. No image is recaptured to repair a thumbnail.

On reopening the saved card, pending intents are listed. **Повторить сохранение** resumes promotion/commit/thumbnail generation with the same UUIDs; a commit already present is a verified no-op. If a staging write failed before bytes existed, **Выбрать тот же файл для восстановления** accepts only bytes matching the saved hash and size. Wrong replacements cannot overwrite evidence. A malformed operation file reports an error and stays on disk for reviewed recovery; it is never silently discarded. Startup does not auto-publish pending imports. Context before an image has been received is an in-memory picker session; cancellation/process termination there creates no accepted image operation.

Every thumbnail/full-screen read first checks original size/SHA-256. Missing/unreadable or changed originals are displayed explicitly, even if a cached thumbnail exists; expected metadata remains intact. **Повторить просмотр** regenerates missing/corrupt thumbnails after the original is available. This stage has no automatic orphan cleanup or user original-file deletion. A crash after intent removal can leave redundant staging bytes; retain them until reviewed cleanup. Never delete the only copy during recovery. If journal load fails, repair/review the saved graph and backups first; the app does not guess a usable revision.

## Received originals and privacy

Files preserves received file bytes. Photos requests the current representation via `PHPickerConfiguration.preferredAssetRepresentationMode = .current`, then copies the provider's file before its temporary URL expires. The provider can still transform it: representation metadata explicitly says library-original identity is unverified. No silent UIImage re-encoding occurs on this path. [Apple's representation contract](https://developer.apple.com/documentation/photosui/phpickerconfiguration-c.class/preferredassetrepresentationmode) documents that limitation.

Camera uses the system camera UI: preserve supplied file bytes when available; if only a UIImage is supplied, explicitly record app JPEG encoding, original encoded bytes unavailable and possible metadata loss. This fallback is never labeled a byte-identical camera original. Record original wall time and offset when provided; see [ImageIO original time](https://developer.apple.com/documentation/imageio/kcgimagepropertyexifdatetimeoriginal). Camera output and physical permissions require owner device verification.

Private received originals may contain personal EXIF/GPS. EXIF GPS is never read into mine coordinates, displayed in ordinary metadata or copied into thumbnails. The app introduces no location permission, GPS positioning, north conversion or viewing-direction inference. Any future workstation export must offer the documented metadata profile and identify sanitized derivatives honestly.

## Complete offline backup (no ZIP exporter yet)

A JSON file alone is **not** a complete backup. With the app closed/no import in progress, retain the entire Application Support/FieldForge directory as a consistent snapshot: mapping graph plus previous/migration backups, every referenced original under `photos/originals`, pending photo intents and staging, all managed DXF files and pending plan intents under `plans`, and the separate `measurements-v1.json` legacy journal plus its backups when present. Thumbnail derivatives are optional and regenerable. UUID-based relative paths must remain unchanged.

A reviewed complete backup also needs an inventory/manifest mapping every attachment UUID to relative path, expected byte size/SHA-256/format and missing/damaged-file status, with photo/point revision relationships retained by the graph. Verify each original and DXF against recorded hashes. Any missing/damaged original or unresolved intent is reported explicitly; such a copy cannot be declared a verified complete backup. P4.1 stores the information needed for that manifest but does **not** generate a package/manifest or implement automated restore. Copying files back blindly over a live/newer journal is not a restore procedure: stage the copy, check graph, hashes, relative paths and pending operations, retain the previous readable directory, then activate only a reviewed consistent snapshot. XLSX/ZIP export and automated package restore remain future work.
