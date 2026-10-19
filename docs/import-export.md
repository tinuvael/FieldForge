# Import/export and spatial integration boundaries

**Pre-MVP owner storage decision:** mapping uses only current experimental schema **7**. No automatic mapping migrations, new `.pN-backup`, resets or deletions; old/corrupt files fail closed and all existing files are preserved. Earlier mapping-schema descriptions below are historical, not supported compatibility. Atomic current saves/`.previous`, integrity, external-change guards and immutable evidence/history remain. The independent original-measurement journal keeps its deployed compatibility. See [current storage/recovery](p4-1-photos.md) and [AGENTS.md](../AGENTS.md).

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

No XLSX library/generation is included now. Later evaluate OOXML implementation or a maintained offline Swift library for license, memory use, precision, escaping and interoperability. Stream rows where possible. Use explicitly typed text UUIDs/metadata, numeric engineering cells, no executable formulas/macros from user strings, documented null/status columns and an export-manifest/schema-version sheet. Keep high-precision original decimal strings alongside Excel numeric cells when Excel's numeric precision would lose information.

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

## Offline geological photo package (future)

Photo export serves Mapping and Plan using `SpatialObservationPoint`, `PhotoObservation` and `Attachment` UUIDs from the shared database. It does not create a fourth module or require georeferencing/GPS. Produce a ZIP for workstation use from a consistent record/location-revision snapshot:

```text
FieldForge-Photos-<export-id>.zip
  manifest.json
  PhotoRegister.xlsx
  PhotoRegister.csv                optional
  images/<attachment-uuid>/original.<actual-format-extension>
  thumbnails/<attachment-uuid>/preview.<format>   optional
  derivatives/<attachment-uuid>/sanitized.<format>   optional, explicitly labeled
```

Original filenames and editable photo names/numbers are metadata, not identity or archive paths. Use stable relative UUID-based image paths, deduplicate by attachment ID when several records reference one image, and prohibit absolute/traversal paths. No workstation path or device sandbox absolute path should be required to resolve a package. Derivatives have their own IDs/hashes and source lineage; no silent crop, recompression or metadata-stripping of a file labeled original.

The XLSX register includes one row per selected photo, including photos with unknown coordinates, absent interval/point or missing image bytes:

| Columns | Meaning |
| --- | --- |
| Photo ID, name, number | Stable UUID plus editable presentation metadata |
| Project, excavation | IDs and human-readable names from the export snapshot |
| Mapping interval, observation point | Optional IDs/names, interval chainage and point/location revision; missing links stay blank |
| Chainage, X, Y, Z | Numerical meters/declared coordinate units where available; null is blank, never zero |
| CRS, coordinate source/reliability | Explicit CRS/units/axes and surveyed/plan-derived/manual/unknown provenance with quality/uncertainty |
| Capture timestamp/source | UTC instant when established, preserved source/timezone or missing/uncertain state; import time is a separate field |
| Description, category | Original register text/category, spreadsheet-formula protection applied to text |
| Relative image path | Managed package path and original filename metadata; unavailable image state is explicit |
| Attachment integrity | Original attachment ID, actual MIME/format, dimensions, expected byte size, hash algorithm/digest and verification/availability status |

The machine-readable manifest is versioned and preserves exact IDs/relationships, input location revisions, null reasons, north/provenance for optional viewing direction, original numerical values/timestamps, metadata profile, archive-entry hashes/sizes and any omissions. Keep exact numeric strings alongside Excel numeric cells where Excel's precision would lose information. Optional CSV uses the same logical register fields with documented encoding/escaping. XLSX/CSV alone are not complete backups and this phase adds no XLSX generator.

### Privacy, missing files and recovery

Original imported images may contain personal EXIF GPS or photographer information. Preserve the best available original privately for evidence, but do not read EXIF GPS into mine coordinates or expose private metadata in ordinary registers/thumbnails. The export profile must make original-byte inclusion and its embedded metadata explicit. A privacy-reviewed original-image package includes originals under that profile; when removing personal EXIF is chosen, create and identify sanitized derivatives, record omitted originals/fields and their lineage, and never call that privacy-reduced package a complete original backup. Preserve relevant capture/orientation metadata without inventing a viewing azimuth or silently converting its north reference.

Verify each available original's size/hash before packaging. Missing/unreadable/hash-mismatched files retain their register/manifest rows, expected IDs/paths/hashes and clear error status. Offer repair/retry or an explicitly incomplete package with an omission report; never declare a package complete or drop a record because coordinates/image bytes are unavailable. Write into staging, support cancellation/progress with bounded memory, close and verify the archive before promotion, and preserve recoverable state on failure. Source images and records are not changed by export.

A complete offline backup contains all referenced original images, database/record snapshot, point/location revisions, metadata and attachment manifest/hash information. Thumbnails may be included or regenerated; missing originals make a backup explicitly incomplete. Restore into staging, validate file hashes, path safety and relationships, report unavailable assets, and promote only a validated/reviewed state. Attachment import, promotion, thumbnail generation, archive cleanup and restore must be recoverable after interruption; see [architecture](architecture.md). These are future requirements, not an implemented photo workflow.

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
