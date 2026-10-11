# Import/export and spatial integration boundaries

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

Add `InterpretationEvidence` (representative/structure ID ↔ measurement ID, role/provenance) and `Attachments` sheets/manifests when those entities exist; comma-separated IDs in a cell are not the canonical relationship model. Photos/meshes can travel as external attachments in a reviewed export bundle. No completeness filter should remove otherwise valid parent rows.

## Other planned engineering formats

- **CSV:** one table per entity plus a manifest for future multi-table exports; current observation CSV remains available.
- **DIPS-compatible orientation tables:** target a documented Rocscience DIPS version/import configuration. Explicitly select dip-direction/dip (not strike/dip), units, common north and treatment of horizontal/vertical convention cases. Do not mix magnetic/true/grid/unknown/synthetic entries silently. Partition by reference or request documented conversions; return an exclusion report. Include IDs/provenance in a sidecar if the format cannot represent them. Compatibility needs a real DIPS import test before claiming support.
- **Structured JSON backup/interoperability:** independent schema version, complete entities, relationships, null reasons, original diagnostics/inputs, method versions, spatial metadata and attachment hashes. Preserve timestamps/IDs and numeric values; stage/validate imports and maintain migrations. Use a consistent snapshot and ZIP/package manifest for attachments, not just observation CSV.

## Spatial format capabilities and limitations

| Format | Proposed role / limitations |
| --- | --- |
| DXF | Survey lines/polylines/arcs/alignment geometry after handling units, layers, coordinate-system sidecar, unsupported entities and station metadata. No native parser added. |
| DWG | Use an appropriate licensed SDK (e.g. reviewed ODA/Autodesk workflow) or desktop conversion to a documented interchange format. Do not assume native reading, license availability or lossless conversion. Preserve conversion provenance and inspect units/entities. |
| STL | Triangle surfaces; **no standardized CRS/georeferencing metadata**, often no reliable units. Require explicit units/CRS sidecar. It is not an alignment or surveyed chainage definition. |
| OBJ | Mesh/UV/material data; coordinate/length/georeferencing conventions need explicit metadata; retain associated MTL/textures. |
| PLY | Mesh/point attributes with format variants; require declared coordinate/units and adapter validation. |
| GeoJSON | Geographic vector exchange under RFC 7946 WGS84 longitude/latitude; local-grid values require verified conversion or a different structured format. Not a large triangle-mesh interchange. |
| Structured JSON | Versioned mine geometry/CRS/alignment metadata and references to binary chunks/assets. Explicit units and transform lineage. |

## Native frameworks and processing split

[Model I/O](https://developer.apple.com/documentation/modelio) handles 3D asset/mesh/material processing, not arbitrary CAD drawing semantics, mine CRS or chainage. Check runtime support with `MDLAsset.canImportFileExtension`/`canExportFileExtension` for the target OS rather than promise all listed formats. Imported assets need validation for units, axes, topology and attributes. Model I/O does not provide a general DWG/DXF survey pipeline.

[RealityKit](https://developer.apple.com/documentation/realitykit) is a native rendering/entity/interaction and AR integration layer; prepare supported assets (often USD/USDZ) and manage mesh/material conversion separately. It is not a survey interpolation engine, GIS datum library or universal CAD reader. [ARKit](https://developer.apple.com/documentation/arkit) device-local tracking does not establish underground georeferencing or geological accuracy. Metal/custom buffers may later help controlled rendering of prepared chunks; do not create a viewer in this phase.

On iPhone: validate compact prepared metadata/assets, query nearby intervals, interpolate an already supported surveyed alignment in later phases, select/render bounded chunks with local origins/LOD, and export observations offline. Avoid loading full mines/meshes into memory: spatial indices, bounding volumes, tiled assets, bounded caches, background decode and cancellation should precede large-model support.

On desktop: licensed DWG conversion, complex DXF entity resolution, verified CRS/datum transformation with survey control, mesh cleaning/triangulation/decimation, spatial tiling/LOD, texture preparation and packaging manifests/checksums. Deliver explicit units, model origin, CRS, alignment version and source→model transform to the phone. Device display coordinates remain separate from authoritative Double-precision engineering coordinates. No parser, conversion SDK or 3D viewer is implemented here.
