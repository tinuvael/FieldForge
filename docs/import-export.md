# Import/export and spatial integration boundaries

**Current update (2026-10-21):** [Final field polish](final-field-polish.md) supersedes the historical default-export, sheet-order and input-only RMR descriptions below. Excel is the default, with five Russian field sheets and preserved technical sheets. Verified preliminary RMRbasic categories are available under a separate method version; legacy inputs stay unchanged.

**P5.1 implemented:** [Project mapping CSV contract](p5-1-mapping-csv.md) defines project/optional horizon/excavation selection, inclusive field dates in an explicit time zone, a frozen effective-version snapshot, 14 related CSV tables and manifest, native sharing, photo metadata only and precision/formula handling. This is separate from the standalone measurement CSV below. **P5.2 implemented:** [Native offline XLSX](p5-2-mapping-xlsx.md) uses that same typed snapshot, adding a Russian summary, 14 relational sheets, styles, filters and exact-text precision protection. Original-photo packages remain planned.

**Pre-MVP owner storage decision:** mapping uses only current experimental schema **8**. No automatic mapping migrations, new `.pN-backup`, resets or deletions; old/corrupt files fail closed and all existing files are preserved. Earlier mapping-schema descriptions below are historical, not supported compatibility. Atomic current saves/`.previous`, integrity, external-change guards and immutable evidence/history remain. The independent original-measurement journal keeps its deployed compatibility. See [current storage/recovery](p4-1-photos.md) and [AGENTS.md](../AGENTS.md).

**P4.1 implementation update:** [Saved-point photographs](p4-1-photos.md) supersedes the future-only photo statements below for saved observations. Schema 7 adds photo/attachment and metadata-revision arrays to the existing journal, freezes exact P3.3 point revisions, and implements offline recoverable imports, gallery and zoom. Draft-point/point-free photos, XLSX/ZIP packages and automatic backup/restore remain future work. JSON alone is not a complete backup; include original photographs, DXF, pending operations and a verified inventory/manifest.

The authoritative [product vision](product-vision.md) restricts the product to Geomechanical Mapping, Excavation Plans & Spatial Positioning, and Wedge Analysis on a shared offline project database, with future native iPad support. Prepared plans and engineering records are primary exchange needs; DWG editing, general-purpose CAD/GIS and full 3D mine modeling are outside scope. Current CSV behavior below is unchanged; the other adapters remain plans.

## Common boundary (future interfaces)

Use format adapters around a versioned domain snapshot, rather than exposing persistence or renderer internals. A future import request carries file URLs/streams, detected format/version, explicit CRS/units/axis metadata, conflict policy and attachment manifest. An import report returns accepted/rejected IDs, missing data, transformations and warnings; stage and validate before transactional promotion. Cancellation or an unsupported format must leave the journal intact. Preserve source file hash/name and conversion provenance. Reimport should resolve stable source IDs through a reviewed merge policy, not deduplicate orientations solely by angle/time.

A future export request selects IDs/snapshot, format and convention policy; exporters return a file/manifest plus omitted/unsupported-field diagnostics. Relationships use UUIDs. Preserve incomplete intervals and null parameters; distinguish not observed, not applicable, not calculated and invalid. Never make an incomplete assessment appear zero-valued or silently drop an interval with no orientations. Keep export creation off the main actor at future large scale, reading a consistent snapshot with bounded-memory batches and progress/cancellation. These interfaces are design only in Phase 2.

## Operational CSV in Phase 2

UTF-8 BOM, commas, CRLF records, quoted fields, doubled embedded quotes and ISO 8601 UTC timestamps with milliseconds. Numeric values use locale-independent round-trip Double strings, not display rounding (scientific notation can occur). Missing numbers are empty; zero remains zero. Notes/original input text that could be spreadsheet formulas receive an apostrophe; signed numeric diagnostics remain numeric. CSV text is for analysis, not exact reconstruction of arbitrary original strings.

The first 24 Phase 1 column names/order remain; four columns are appended:

| New column | Meaning |
| --- | --- |
| `measurement_source` | `iPhoneSensor`, `manualCompass`, `simulatorMock`; external source reserved |
| `dip_direction_meaning` | `downhill`, `undefined`, `conventionalDipSide` |
| `original_dip_direction_text` | Original manual text, e.g. 360 before normalization |
| `original_dip_angle_text` | Original manual text, including decimal comma |

`geographic_reference` carries magnetic/true/grid/unknown or historical unavailable/simulated metadata. `sensor_source` remains the legacy raw adapter source and is blank for manual. Manual sensor frame, magnetic/motion diagnostics, matrix, quaternion, normal and gravity cells are empty; the geological plane is not an iPhone screen. Orientation columns remain dip direction then dip angle in degrees. Export does not convert north or turn a vertical convention into a uniquely measured downhill direction. Consumers must read the header and tolerate additional columns/new enums and full-precision numeric formatting. Excel may round numeric cells at its own precision limit; original JSON remains authoritative.

## Planned workbook

P5.2 now implements dependency-free streaming OOXML/ZIP generation; the [XLSX contract](p5-2-mapping-xlsx.md) supersedes the future design below for current mapping records. Stream rows where possible. Use explicitly typed text UUIDs/metadata, numeric engineering cells, no executable formulas/macros from user strings, documented null/status columns and an export-manifest/schema-version sheet. Keep high-precision original decimal strings alongside Excel numeric cells when Excel's numeric precision would lose information.

| Worksheet | Primary key / relationships / content |
| --- | --- |
| Projects | `project_id`; names, site, CRS/mine-grid definitions or metadata references |
| Excavations | `excavation_id`, `project_id`; type, horizon/elevation/datum, alignment ID/version |
| Intervals | `interval_id`, `excavation_id`; numeric start/end meters, surface, time, description, missing/attachment references |
| JointSets | `joint_set_id`, `interval_id`; J1–J5, representative dip/direction/reference/convention, interpretation provenance |
| Faults | `structure_id`, `interval_id`; type, thickness meters, absolute chainage, orientation, provenance, description |
| RockMass | `assessment_id`, `interval_id`; original Q inputs, RMR versioned inputs, reference/version, results and missing-data indicators |
| Measurements | `measurement_id`, nullable `interval_id`; original orientation, source, north, quality, notes, original entries and diagnostics references |
| PhotoRegister | `photo_id`, project/excavation/optional interval/point/geological observation IDs; names, capture time, location revision/provenance, image path and attachment integrity |

Add `InterpretationEvidence` (representative/structure ID ↔ measurement ID, role/provenance) and `Attachments` sheets/manifests when those entities exist; comma-separated IDs in a cell are not the canonical relationship model. Photos/meshes can travel as external attachments in a reviewed export bundle. No completeness filter should remove otherwise valid parent rows.

## Other planned engineering formats

- **CSV:** one table per entity plus a manifest for future multi-table exports; current observation CSV remains available.
- **DIPS-compatible orientation tables:** target a documented Rocscience DIPS version/import configuration. Explicitly select dip-direction/dip (not strike/dip), units, common north and treatment of horizontal/vertical convention cases. Do not mix magnetic/true/grid/unknown/synthetic entries silently. Partition by reference or request documented conversions; return an exclusion report. Include IDs/provenance in a sidecar if the format cannot represent them. Compatibility needs a real DIPS import test before claiming support.
- **Structured JSON backup/interoperability:** independent schema version, complete entities, relationships, null reasons, original diagnostics/inputs, method versions, spatial metadata and attachment hashes. Preserve timestamps/IDs and numeric values; stage/validate imports and maintain migrations. Use a consistent snapshot and ZIP/package manifest for attachments, not just observation CSV.

Future exports/backups also retain plan assets/control-point and georeferencing revisions, location provenance and exact input references for wedge analyses. Add related tables/sheets or a versioned manifest as these records are implemented, without replacing the established mapping worksheets. Label geometric/kinematic candidates separately from mechanical assessments and retain unavailable/missing states; geometry-only output must not acquire fabricated stability, safety-factor or risk columns. Mechanical export fields depend on the owner's verified method. Shared exporters work on domain snapshots on both devices, independent of phone/tablet layouts.

## Offline photo export package (P5.3)

Open **Картирование → Журнал → Выгрузка**, select **Фотографии + Excel (.zip)**, keep the existing project / optional horizon / optional excavation / inclusive field-date range / explicit timezone selection, then preview and share through iOS (Save to Files, AirDrop and other destinations).

```text
FieldForge-Photos.zip
  FieldForge-Photos/
    FieldForge-Mapping.xlsx
    manifest.json
    originals/photo-<photo-uuid>.<actual-format-extension>
```

The same frozen P5.1/P5.2 typed snapshot selects the latest effective observation by its field date. All linked photos remain included in the register, including historical point associations, unknown capture time/location and photos imported outside the period. No new filtering engine, database schema, migration or metadata write is involved. Current main uses schema 8 from P4.2; this exporter preserves it.

The workbook contains the existing Russian summary and 14 relational sheets plus a joined **photo_register**. It combines project/horizon/excavation names, current point/picket and field date/zone with every photo/attachment field: stable UUIDs, historical context revision/version, name/number/category/description/source, separate capture/import timestamps, original filename/format/representation, expected and actual size/SHA-256, relative path, integrity/error and archive status. `photos` and `photo_attachments` also receive package-only integrity/path columns; standalone CSV/XLSX contracts remain unchanged. Paths resolve relative to the workbook/manifest directory. A listed path with `archive_included=false` is an expected path, not a file in the archive. UUIDs, not filenames, identify images; duplicate original filenames remain independent.

Unknown capture instants stay blank with **UNKNOWN** in `capture_time_status`, never replaced by import time. `unknownBeforeFirstSave` remains unknown capture location, even when the linked point has coordinates. `photo_point_contexts` retains historical associations; `points` contains the latest selected mapping observations. Existing formula-safe inline text cells, Unicode, nulls, exact date companion seconds and numeric precision rules are reused.

The managed original is opened by attachment UUID. Only regular files at the expected managed path are accepted; symbolic links and unfinished operation intents are refused. Original bytes are read in 256 KiB chunks, counted and hashed with SHA-256 against stored metadata. Export rechecks into private staging and archives those exact chunks without image decoding/recompression, EXIF stripping or thumbnail substitution. At most one original is staged at a time. The existing dependency-free ZIP32 store writer now accepts binary chunks; it rejects unsafe/duplicate entry paths and fails clearly before exceeding 4 GB. ZIP64 and compression are not implemented. Allow temporary disk space for the growing archive plus one original and the workbook.

Preview shows observations, linked photos, verified originals, unavailable/corrupt/unfinished originals and available-original bytes. Every unavailable original retains its UUID and reason in Excel/manifest. A normal export refuses missing/size-mismatched/SHA-mismatched/unreadable/unsafe/unfinished originals. **Only explicit confirmation** permits a partial package: its workbook states **INCOMPLETE**, its manifest has `archive_status: incomplete`, and each omitted file has `included: false` plus its error. If files change after preview, confirmation is requested at generation too. Retry preview after repairing originals/import operations. No automatic source repair occurs.

`manifest.json` uses **FieldForge-Photo-Export/1** and records export UUID, creation/snapshot timestamps, selection/timezone/bounds, counts, overall completeness and each photo/attachment/point/context relationship with expected/actual integrity metadata and included status. No device absolute paths are required. Metadata remains frozen; originals are revalidated at export time.

Hashing and ZIP writing run off the main thread with an activity indicator, single-operation guard and cancellation between chunks. Each operation owns a fresh UUID temporary directory; failure/cancellation removes only that directory. The successful ZIP remains owned through native sharing and is removed after sharing dismisses. Managed originals, intents, databases, DXF and backups are never deleted or changed.

**Privacy:** this explicitly selected original-byte profile includes all embedded private EXIF/GPS, timestamps, orientation and photographer metadata unchanged. The export screen discloses this before sharing. No sanitized derivative profile is provided; the app does not interpret EXIF GPS as underground capture coordinates. Received-byte representation limitations (including Photos provider conversion or camera JPEG fallback at import) remain recorded; export cannot reconstruct an unavailable camera/library master.

This is a **workstation photo export**, not a complete database backup or restore package. DXF originals, pending imports/staging, the independent measurement journal, backups and complete audit history are excluded. Complete verified backup/restore, sanitized derivatives, point-free photos and ZIP64 remain deferred (Issue #23 / later work).

P5.3 verification (2026-10-20): `swift test --filter PhotoPackageExportTests` executed **6 new tests, 0 failures**; one Debug iOS Simulator build succeeded; `git diff --check` passed. Tests use temporary current-schema synthetic records and two distinct generated PNG originals, independently reading ZIP central directories/CRC and XLSX bytes. Existing tests, regression suites, UI tests, Simulator test runs and physical-device/share-destination checks were deliberately not run under the owner's minimal-verification override. Excel application interoperability and physical sharing remain unverified in this change.

## Prepared excavation plans (primary future spatial workflow)

Import PDF and raster plans as versioned attachments with page/image metadata and hashes. Native PDFKit and image rendering are candidates for offline plan display; viewing a page does not georeference it. Store surveyed control points and validated georeferencing separately from annotations/display transforms. A manually selected mark produces model coordinates only when the relevant transform is valid; retain its page/pixel location and unknown/approximate status otherwise. Manual X/Y/Z and alignment chainage use the same location records, never an assumed underground GPS source.

For DXF-derived survey geometry, support a qualified adapter or desktop conversion into a compact prepared format with explicit units, CRS/axes, supported entity inventory, alignment versions and chainage origins/directions. Reject/report unresolved units, missing metadata and unsupported entities. PDF/raster, selected points and bounded survey geometry should work completely offline before optional large-mesh support. On iPad the same prepared assets can support larger plans/split views and optional annotations without introducing another import format or database.

## Spatial format capabilities and limitations

| Format | Proposed role / limitations |
| --- | --- |
| PDF / raster | Primary prepared plan display with page/image metadata; coordinates require surveyed georeferencing or explicit supplied survey transforms, never appearance/scale alone. |
| DXF | Survey lines/polylines/arcs/alignment geometry after handling units, layers, coordinate-system sidecar, unsupported entities and station metadata. No native parser added. |
| DWG | Source preprocessing only through an appropriate licensed SDK (e.g. reviewed ODA/Autodesk workflow) or desktop conversion to a documented interchange format. Direct editing/full CAD is excluded; do not assume native reading, license availability or lossless conversion. Preserve conversion provenance and inspect units/entities. |
| STL (optional) | Triangle surfaces; **no standardized CRS/georeferencing metadata**, often no reliable units. Require explicit units/CRS sidecar. It is not an alignment or surveyed chainage definition. |
| OBJ (optional) | Mesh/UV/material data; coordinate/length/georeferencing conventions need explicit metadata; retain associated MTL/textures. |
| PLY (optional) | Mesh/point attributes with format variants; require declared coordinate/units and adapter validation. |
| GeoJSON | Geographic vector exchange under RFC 7946 WGS84 longitude/latitude; local-grid values require verified conversion or a different structured format. Not a large triangle-mesh interchange. |
| Structured JSON | Versioned mine geometry/CRS/alignment metadata and references to binary chunks/assets. Explicit units and transform lineage. |

## Native frameworks and processing split

[Model I/O](https://developer.apple.com/documentation/modelio) handles 3D asset/mesh/material processing, not arbitrary CAD drawing semantics, mine CRS or chainage. Check runtime support with `MDLAsset.canImportFileExtension`/`canExportFileExtension` for the target OS rather than promise all listed formats. Imported assets need validation for units, axes, topology and attributes. Model I/O does not provide a general DWG/DXF survey pipeline.

[RealityKit](https://developer.apple.com/documentation/realitykit) is a native rendering/entity/interaction and AR integration layer; prepare supported assets (often USD/USDZ) and manage mesh/material conversion separately. It is not a survey interpolation engine, GIS datum library or universal CAD reader. [ARKit](https://developer.apple.com/documentation/arkit) device-local tracking does not establish underground georeferencing or geological accuracy. Metal/custom buffers may later help controlled rendering of prepared chunks; do not create a viewer in this phase.

Compact wedge visualization may use locally generated excavation/candidate surfaces without imported mine meshes. Rendering does not implement geometry feasibility or mechanical stability; those are separate verified services, and mechanics requires the owner's methodology before implementation.

On iPhone and future iPad: display prepared plans, validate compact metadata/assets, select locations/intervals manually, interpolate an already supported surveyed alignment in later phases, visualize local wedge candidates and export observations offline. Optional meshes use bounded chunks/local origins/LOD. Avoid loading full mines/meshes into memory: spatial indices, bounding volumes, tiled assets, bounded caches, background decode and cancellation should precede large-model support. These capabilities support field positioning and local analysis, not a geological modeling platform.

On desktop: licensed DWG conversion, complex DXF entity resolution, verified CRS/datum transformation with survey control, mesh cleaning/triangulation/decimation, spatial tiling/LOD, texture preparation and packaging manifests/checksums. Deliver explicit units, model origin, CRS, alignment version and source→model transform to the phone. Device display coordinates remain separate from authoritative Double-precision engineering coordinates. No parser, conversion SDK or 3D viewer is implemented here.
