# Future geomechanical domain schema

**P2 update:** [P2 mapping and DXF contract](p2-dxf.md) supersedes historical P1 statements about optional horizon elevations, mandatory per-point coordinate strings, absent plans and schema 1. P2 adds nominal Z provenance and immutable managed DXF revisions on the same graph; orientation/measurement conventions are unchanged.

**P1 implementation update:** [Mapping workflow and persistence](p1-mapping.md) describes the implemented project/horizon/multi-horizon-excavation/point graph, context/draft state machine, atomic JSON decision, immutable observations and protected legacy inbox. The Phase 2 descriptions and larger future schema below are historical/design context; they do not override P1's implemented scope.


This is the Phase 2 design for later implementation. Only original orientation observations and their safe persistence are implemented now. All entities use stable UUID primary keys, explicit foreign-key relationships, UTC instants, finite unrounded engineering numbers, and explicit units. Missing data is null with a reason, never an invented zero or rating. Distinguish original field inputs, calculated outputs, and interpreted representatives.

The [product vision](product-vision.md) is authoritative for requirements: this shared domain serves exactly Geomechanical Mapping, Excavation Plans & Spatial Positioning, and Wedge Analysis on iPhone and future native iPad. The planned records below are documentation, not changes to the deployed JSON schema.

```mermaid
erDiagram
    Project ||--o{ Excavation : contains
    Excavation ||--o{ MappingInterval : maps
    MappingInterval ||--o{ RockMassAssessment : assesses
    MappingInterval ||--o{ JointSet : interprets
    MappingInterval ||--o{ TectonicStructure : records
    MappingInterval o|--o{ OrientationObservation : locates
    JointSet o|--o{ InterpretationEvidence : cites
    TectonicStructure o|--o{ InterpretationEvidence : cites
    OrientationObservation ||--o{ InterpretationEvidence : supports
    Project ||--o{ SpatialObservationPoint : locates
    Excavation ||--o{ SpatialObservationPoint : contains
    MappingInterval o|--o{ SpatialObservationPoint : associates
    SpatialObservationPoint o|--o{ PhotoObservation : documents
    MappingInterval o|--o{ PhotoObservation : associates
    OrientationObservation o|--o{ PhotoObservation : illustrates
    Attachment ||--o{ PhotoObservation : originalImage
```

## Project / mine

| Field | Type / meaning |
| --- | --- |
| `id` | UUID |
| `name`, `siteName` | Project and mine/site names |
| `crs` | CRS metadata: authority/code or WKT/version, datum/epoch where relevant, axis order, length units, vertical datum and north convention; explicitly unknown if not established |
| `mineCoordinateSystem` | Optional local origin, axes, handedness, length units, height definition and georeferencing transform with provenance/version; see coordinate document |

## Excavation

| Field | Type / meaning |
| --- | --- |
| `id`, `projectID` | UUID, required parent FK |
| `name` | Excavation name |
| `horizonName`, `elevationMeters` | Optional named horizon and numeric elevation with vertical-datum reference; a named horizon is not automatically a surveyed height |
| `type` | Versioned controlled type (e.g. drift, crosscut, shaft, open-pit exposure, other with description); no engineering rating implied |
| `surveyAlignmentID` | Optional spatial alignment FK including alignment version |

## Mapping interval

| Field | Type / meaning |
| --- | --- |
| `id`, `excavationID` | UUID, required parent FK |
| `startChainageMeters`, `endChainageMeters` | Finite numerical meters; end > start along the declared alignment direction |
| `observationPosition` | `leftWall`, `rightWall`, `roof`, `face`, `other`; other requires a description |
| `timestamp`, `description` | Observation instant and field description |
| `photoIDs` | Optional `PhotoObservation` UUID relationships; images are separate managed attachments |
| `alignmentVersionID` | Optional snapshot reference preventing later survey edits from silently relocating observations |

Excavation name and horizon are presented through `excavationID` and the relevant parent revision rather than re-entered in each module. Planned location relationships below let the plan select this same interval and the wedge module consume its geometry/joint-set revisions.

Chainage is independent of strings such as «ПК 0+005». Define a display policy's picket length/precision and parse it explicitly if ever used for input. Typical interval lengths are 5–10 m; **no such length restriction is imposed**. Left/right follow increasing chainage, including explicit rules for branches/shafts; missing alignment leaves position unlocated rather than fabricating coordinates. Overlaps can be legitimate for different surfaces/dates; flag them for review instead of deduplicating by range.

Describe joint characteristics such as spacing, persistence, roughness, infill, weathering and water conditions primarily at interval level in field descriptions or later verified structured fields. Do not require separate entries for each representative orientation.

## P3.2b implemented rock-mass assessment

Schema 5 adds optional `MappingObservation.ratings` containing `BartonQAssessment` and `RMR89Assessment`, each revision 1 with method/implementation version, timestamp and exact original input strings/source notes. Q stores a validated result snapshot (original/used RQD, effective coefficients, unrounded Q, seven-class value or outside-chart null) or an explicit missing list. RMR89 stores original inputs/missing list only, with numerical evaluation unavailable. Existing observations decode ratings as nil. Assessments belong to the immutable point/optional interval; no link or result is added to fracture measurements. See [exact tables, validation and migration](p3-2b-ratings.md).

## Rock-mass assessment (future independent revision entities)

`id` and required `mappingIntervalID`; assessments belong to an **interval**, never each individual joint measurement. Retain assessment revisions rather than overwrite field evidence.

- Q inputs: nullable `RQD`, `Jn`, `Jr`, `Ja`, `Jw`, `SRF`, each with original entry/value, units or dimensionless meaning, missing reason, source and observation notes. Preserve conflicting/incomplete inputs for review without calculating a class.
- Optional RMR assessment: selected published method/version/reference plus its original parameter inputs and evidence. RMR versions are not interchangeable; reserve a versioned parameter payload, without inventing rating tables.
- `method`, `classificationVersion`, bibliographic reference (edition/revision/page or table), assessor and timestamp.
- Separate nullable `calculatedResult`, result units/class, calculation implementation version/input snapshot, missing-data list and validation diagnostics.
- Optional interval field description.

**No Q or RMR calculation or empirical scale is implemented in Phase 2.** Future implementation must verify the specific publication/version and boundary cases. Candidate primary references for review: Barton, Lien & Lunde (1974), *Engineering classification of rock masses for the design of tunnel support*, Rock Mechanics 6, 189–236, DOI [10.1007/BF01239496](https://doi.org/10.1007/BF01239496); Bieniawski (1989), *Engineering Rock Mass Classifications*, Wiley. These citations do not authorize unverified transcription of scales or assuming all later Q/RMR revisions are equivalent.

## Representative joint sets

`id`, required `mappingIntervalID`, `identifier` in J1–J5; enforce uniqueness of `(mappingIntervalID, identifier)` and at most five representatives. Store representative dip angle, nullable dip direction, north reference and direction meaning. Include interpretation provenance: interpreter/time, selected method/reference/version if computed, rationale/notes, and optional links to multiple **original observations** through `InterpretationEvidence`.

A representative may be manually interpreted without constituent observations; that absence is explicit. Five measurements are not automatically five statistical sets. Editing a representative does not overwrite or relabel its original measurements. Do not average azimuths arithmetically or combine different north references without documented corrections. Uncertainty and sampling adequacy must be addressed before implementing statistical grouping.

An `InterpretationEvidence` record has its own UUID, a required `measurementID` FK and exactly one target FK (`jointSetID` or `tectonicStructureID`, enforced as an exclusive choice), plus role and interpretation provenance. The target and measurement must belong to the same interval when linked; an unassigned observation must be explicitly located before creating such evidence.

## Faults / tectonic structures

`id`, required `mappingIntervalID`, controlled `structureType` with an `other` description, nullable orientation fields when incomplete, `thicknessMeters`, `positionChainageMeters`, optional description and measurement/interpretation provenance. Thickness is finite and nonnegative when known; unknown is null. Store position as absolute chainage within the interval, with an optional explicit offset derived from its start; position must fall in the declared interval when known.

Allow multiple structures with **no arbitrary count limit**. Optional evidence links reference original orientations. A fault's interpreted orientation and an instrument observation remain distinct values. North/convention metadata travels with both.

## Original orientation observation

| Field | Type / meaning |
| --- | --- |
| `id`, `timestamp` | Stable capture UUID, observation instant |
| `dipAngleDegrees` | Finite 0–90° when known; Phase 2 saved observations require it |
| `dipDirectionDegrees` | Nullable; normalized [0,360)°, with original manual entry retained |
| `measurementSource` | `iPhoneSensor`, `manualCompass`, `externalInstrument`, `simulatorMock`; only the first, second and fourth currently supported |
| `referenceNorth` | Magnetic / true / grid / unknown; historical unavailable/simulated states retained explicitly |
| `directionMeaning` | Downhill / undefined / conventional vertical dip side |
| `sensorDiagnostics` | Optional sample (frame, matrix, quaternion, gravity, magnetic diagnostics, motion, uptime); absent for manual |
| `quality`, `uncertainty` | Explicit status; optional later physical uncertainty value/unit, method/confidence/reference. Absence is not zero uncertainty |
| `originalManualInput` | Optional original text, selected north and convention flag |
| `notes`, `plane`, `algorithmVersion` | Original notes and processing metadata; manual plane is geological, not iPhone screen |
| `mappingIntervalID` | Optional FK; deployed standalone journal observations remain valid |
| `relationship links` | Optional joint-set/tectonic evidence links; use join records with role/provenance rather than copy UUIDs into unstructured text |

For future partially mapped intervals, keep the interval, descriptions and incomplete structures even if there are no savable orientations. The current journal's stricter capture validation does not prescribe deleting incomplete future domain records. Record revisions/import lineage should preserve the original payload and author/time; deletion, correction and interpretation need explicit semantics.

## Prepared plans and location records (future)

| Planned record | Fields / relationships |
| --- | --- |
| `PlanAsset` | UUID, project FK, associated excavation IDs, source/format (PDF/raster/prepared DXF-derived geometry), attachment/hash, page/layer/geometry revision and original metadata |
| `SurveyControlPoint` | UUID, plan revision FK, source point/page coordinates and surveyed X/Y/Z as available, CRS/units/axes, survey source/version, quality and timestamp |
| `GeoreferencingRevision` | UUID, source plan revision, control-point revision IDs, source/target CRS, units/axes, transformation method/version/parameters, residuals, validity extent and author/time |
| `ObservationLocation` | UUID/revision, project/excavation FKs, interval or original-observation FK, optional plan mark/page, nullable X/Y/Z, CRS/units/axes, source/quality, survey/transform revision, optional chainage/alignment version and origin/direction |

Location derivation is explicit: surveyed, georeferenced-plan-derived, manually entered, or unknown. Record approximate quality independently, including source/uncertainty and missing-data reasons. Manual entry may cite surveyed coordinates; plan-derived does not mean independently surveyed. Ungeoreferenced plan marks retain their page/asset coordinates and unknown model position. A 2D plan does not supply Z by default. Unknown elevation must not become zero, a horizon label or a device altitude. The interval/observation target must be in the declared excavation/project; revision and evidence links prevent unrelated coordinate systems from being combined silently.

Control points, transformations and locations retain their original values and explicit revision history. A later plan/survey revision does not move existing evidence automatically. Selecting a saved plan location resolves the existing interval ID; it does not duplicate mapping data. No underground GPS/device-location inference is part of this model.

## Spatial observation points and photographs (future)

These definitions support Mapping and Plan workflows in the same iPhone/future-iPad data architecture. They are a conceptual contract, **not a deployed schema change**. A `SpatialObservationPoint` is the stable named field point; `ObservationLocation` supplies its versioned coordinate/plan-mark evidence. Coordinates listed below refer to the selected location revision rather than a second independently editable coordinate store.

| `SpatialObservationPoint` field | Meaning |
| --- | --- |
| `id`, `projectID`, `excavationID` | UUID and required consistent parent FKs |
| `mappingIntervalID`, `name` | Optional interval FK and user-visible point name |
| `locationRevisionID`, `x`, `y`, `z` | Location revision FK; X/Y when known and optional Z, finite and unrounded; all coordinates may be null for an unlocated point |
| `crs`, `coordinateProvenance`, `reliability` | CRS/units/axes and surveyed/plan-derived/manual/unknown source; approximate/unknown quality, uncertainty and source evidence separately |
| `chainageMeters` | Optional numeric chainage with origin/direction metadata; never inferred from a filename |
| `planID`, `planVersionID`, `alignmentVersionID` | Optional survey-plan and alignment revision references; an ungeoreferenced point may retain page/pixel coordinates |
| `timestamp`, `notes` | Field point instant and notes, with revision author/time for corrections |

| `PhotoObservation` field | Meaning |
| --- | --- |
| `id`, `projectID`, `excavationID` | Stable UUID and required consistent context FKs |
| `mappingIntervalID`, `spatialObservationPointID`, `geologicalObservationID` | Optional UUID links to interval, point and original geological observation; when multiple links exist, their parents must agree |
| `name`, `photoNumber` | Editable display name and field number; neither is record identity or a filesystem key |
| `captureTimestamp`, `captureTimeProvenance` | Original capture instant/timezone or uncertainty where supplied; unknown if unavailable, never silently replaced by import time |
| `description`, `category` | Editable description and optional roof/leftWall/rightWall/face/joint/fault/generalCondition/other category |
| `originalImageAttachmentID`, `thumbnailAttachmentID` | Required original attachment FK; thumbnail FK may be pending/unavailable and generated recoverably |
| `photographer` | Optional photographer metadata, included in exports only under the selected metadata profile |
| `viewingDirection` | Optional azimuth, north reference, acquisition/source provenance and quality; unknown direction remains absent |
| `pointLocationRevisionID`, `createdAt`, `importMetadata` | Optional location revision at capture, registration/import time and source lineage; do not silently move old photos when point coordinates are revised |

| `Attachment` field | Meaning |
| --- | --- |
| `id`, `originalFilename` | Stable UUID and original filename as metadata only |
| `managedRelativePath` | Application-managed local path relative to its attachment root, independent of display/original names |
| `format`, `mimeType`, `byteSize` | Actual file format/MIME type and byte count |
| `pixelWidth`, `pixelHeight` | Image dimensions where applicable; orientation metadata retained for correct viewing |
| `integrityHash`, `hashAlgorithm` | Content digest (e.g. SHA-256) and algorithm identifier for import, backup and export verification |
| `createdAt`, `importMetadata` | Creation/import source and time, original metadata and any transcoding/original-unavailable limitation |
| `thumbnailAttachmentID`, `derivedFromAttachmentID` | Optional thumbnail/derivative relationships; derived files never replace the original |
| `availability` | Explicit staged/available/missing/damaged state for recoverable operations, never deletion of a missing photo's record |

One point has many photo observations; each photo may have one point or none. Point and photo parent relationships must resolve to the same excavation/project and, where assigned, consistent intervals. Assign the selected context at capture/import start; use idempotent operation IDs to avoid duplicate records on retry. File names/numbers may repeat without conflating UUIDs. Point-free or unlocated photographs remain valid and exportable. Register edits use controlled metadata revisions; original bytes and their hashes stay intact. Photo viewing direction is independent from measured geological plane orientation.

Attachments are not inline database image blobs or external Photos-library references: copy accepted imports into managed offline storage. Keep private original EXIF when practical; separately control metadata exposed in exports, especially personal GPS/photographer details. Do not infer mine coordinates from EXIF. Backups include records, original images, hashes and relationships; thumbnails are regenerable when originals exist. Missing/corrupt files are explicitly reported and records retained, with recovery described in [architecture](architecture.md) and the [export contract](import-export.md).

## Wedge inputs and derived results (future)

| Planned record | Fields / relationships |
| --- | --- |
| `ExcavationGeometryRevision` | UUID, excavation FK, axis azimuth/north and inclination convention, cross-section type/dimensions/units, surfaces/extent/position assumptions, optional survey/alignment revision and provenance |
| `JointMechanicalInput` | UUID/revision, representative joint-set revision or analysis-local plane FK, planned cohesion/friction values with units/source/reference, missing indicators and method-required additional inputs |
| `WedgeAnalysisRun` | UUID, project/excavation FK and optional interval FK, exact geometry and joint-set revisions or explicit manual input revisions, immutable input snapshot, reference/frame metadata, selected method/version, author/time and assumptions |
| `WedgeGeometryResult` | UUID, analysis-run FK, geometric/kinematic method and implementation versions, candidate planes/intersections, roof/wall context, finite/unbounded/indeterminate state, geometric assumptions and missing inputs |
| `WedgeMechanicalResult` | UUID, analysis-run and geometric-result FKs, mechanical input revisions, method/reference/implementation versions, separate availability/validation state and outputs allowed by the verified method |

This is a conceptual record contract; mechanical units, output fields and any additional parameters must be finalized against the **owner-provided, verified formulation**. Do not invent equations, ratings, factors of safety or thresholds. An unavailable mechanical result is distinct from geometric infeasibility or a stable wedge. A bounded-volume result requires documented plane positions/bounds/persistence and release assumptions as applicable; orientations alone do not establish actual finite volume.

Automatic input loading means reading available shared records by stable ID, then reporting missing geometry/strength/reference information. Analysis-specific overrides create versioned inputs rather than edit mapping evidence. Referenced originals remain immutable; controlled corrections preserve prior revisions and reason/author/time. Interpretations and results reference exact revisions and become historical/need recalculation when source revisions change. The present Phase 2 deletion behavior is unchanged; a future archive/revision policy must protect evidence used by saved analyses. Shared record definitions support both device families without introducing synchronization or a new database in this PR.

## Implemented P3.1 point evidence

Mapping schema 3 stores original `Measurement` values in the shared mapping aggregate. `MappingObservation.measurementIDs` owns ordered UUID references; every original has exactly one point owner, inheriting its project/horizon/excavation context. Manual input and raw sensor diagnostics retain their original source, precision, north and timestamp. Originals and points are append-only. P3.2a adds explicitly interpreted representative sets separately from these originals; see the implementation update below. See [P3.1 capture/storage](p3-measurements.md).

## P3.2a implementation update

The shared mapping aggregate now uses schema 4 with optional `MappingGeology` on immutable points: interval bounds/position, interpreted J1–J5 revision-1 records with point-local original-evidence UUID links, and arbitrary tectonic structures. Original measurements remain separate immutable evidence. The existing atomic aggregate and backup mechanism is extended without a new storage layer; legacy observations retain absent geology. See [P3.2a domain, units and persistence](p3-2a-geology.md). Planned relational entities elsewhere in this document remain future architecture.

Tectonic orientation may be complete, dip-only, azimuth-only or unknown using the same schema-4 orientation text/north/convention fields. Blank angle text is unknown, not zero. Partial validation does not yield a determined plane or weaken the original-measurement/J1–J5 validators. Left/right wall positions refer only to increasing chainage, not a geographic heading or coordinate axis. This clarification adds no schema version or migration.
