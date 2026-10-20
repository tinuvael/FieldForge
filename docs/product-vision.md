# FieldForge product vision

**W1 implementation update:** the existing «Клинья» tab now provides transient straight-excavation and schematic interpreted-joint visualization. Finite wedges, mechanics and saved scenarios remain deferred. See [W1 geometry and limits](w1-geometry.md).

**Pre-MVP owner storage decision:** mapping uses only current experimental schema **8**. No automatic mapping migrations, new `.pN-backup`, resets or deletions; old/corrupt files fail closed and all existing files are preserved. Earlier mapping-schema descriptions below are historical, not supported compatibility. Atomic current saves/`.previous`, integrity, external-change guards and immutable evidence/history remain. The independent original-measurement journal keeps its deployed compatibility. See [current storage/recovery](p4-1-photos.md) and [AGENTS.md](../AGENTS.md).

**P4 implementation update:** [Saved-point photographs](p4-1-photos.md) and [new-observation draft photos](p4-2-draft-photos.md) supersede future-only photo statements below. Draft photos commit atomically with their first point and retain unknown capture-location provenance. Saved-point imports retain exact P3.3 point revisions. Point-free photos, XLSX/ZIP packages and automatic backup/restore remain future work. JSON alone is not a complete backup; include original photographs, DXF, pending operations and a verified inventory/manifest.

This is the authoritative source for intended product requirements and scope. Technical documents describe how to realize this vision; the [README](../README.md) and [verification report](phase2-verification.md) describe implemented and verified behavior. Future requirements below are not claims of available features or engineering validation.

## Purpose and boundaries

FieldForge is a professional, offline-first geological and geomechanical field mapping application for iPhone, with future native iPad support from one codebase. It replaces paper mapping journals, simplifies surveyed spatial reference inside underground excavations, and provides compact preliminary wedge analysis. It remains a focused engineering field instrument. Russian is the user-interface language; code identifiers and technical documentation are English.

The product has **exactly three primary functional modules**, operating on one consistent project database:

| Module | Purpose | Target Russian navigation |
| --- | --- | --- |
| Geomechanical Mapping | Record intervals, original observations, interpretations and rock-mass characterization | Картирование |
| Excavation Plans & Spatial Positioning | Place and retrieve mapped observations on prepared excavation plans | План |
| Wedge Analysis | Review candidate geometric configurations and, when a verified method is available, separate mechanical assessments | Клинья |

Project selection and settings belong in secondary navigation. Measurement, interpretation, export and backup are shared capabilities or workflows within these modules, not additional primary modules. P2 opens «Картирование / План / Клинья» with mapping and offline 2D horizon DXF plans; Wedge remains explicitly unavailable. Measurement, the unassigned legacy journal and settings are secondary navigation.

## 1. Geomechanical Mapping

### Interval-centered field workflow

Use **Project / Mine → Excavation → Mapping Interval**. An interval presents its excavation name and horizon through explicit parent relationships; historical references must retain the relevant parent revision. It records:

- Numerical start/end chainage in meters and observation position: roof, left wall, right wall, face or other.
- Date/time, geological description and optional photographs.
- Original orientation observations and interpreted representative joint sets.
- Interval-level rock-mass assessment and general joint-condition descriptions.
- Multiple tectonic structures with type, dip/direction, thickness, location and description.

Typical intervals are 5–10 m, but arbitrary valid lengths are supported. Display strings such as «ПК 0+005» do not replace numerical chainage or its documented origin/direction. Retain incomplete intervals and missing-data reasons without inventing zeros or ratings.

### Orientations and interpretations

Support automatic iPhone Core Motion capture where hardware is available and manual geological-compass entry. Every observation records source, timestamp, magnetic/true/grid/unknown north, quality and available original diagnostics or manual inputs. Preserve numerical precision and undefined directions; no silent north conversion. Device availability or display resolution is not validated accuracy.

Allow up to five representative sets **J1–J5 per interval**, each optionally linked to multiple original observations. Representatives are explicit interpretations with author/time, method/version where applicable and evidence links. Five observations do not automatically constitute five statistical sets. Original observations remain independent evidence and are never overwritten by interpretation or analysis.

### Rock-mass characterization

Record Barton Q inputs **RQD, Jn, Jr, Ja, Jw, SRF** and optional RMR using an explicitly selected published version. General joint conditions primarily belong to the interval, not a repeated form for every representative set. Q/RMR assessments also belong to the interval. Support multiple tectonic structures without arbitrary count limits.

Before implementing any classification calculation, document and verify the published method, edition/version, rating tables, applicable assumptions and independent engineering examples/tests. Never invent coefficients, methods or scales. Keep original inputs, calculated results and missing-data indicators distinct.

### Export and preservation

Provide future XLSX workbooks, related CSV tables, version-qualified DIPS-compatible orientation files and structured offline backups. Preserve stable IDs, relationship/evidence links, provenance, north/direction conventions and original numerical precision. Export incomplete intervals with explicit null/status fields; report exclusions or unsupported fields. Backups include original observations, plan/georeferencing metadata, versioned interpretations/analyses and referenced attachments. Analysis tables do not substitute for a complete backup.

### Geological photo documentation (core future capability)

Photo documentation is integrated into **Geomechanical Mapping** and **Excavation Plans & Spatial Positioning**, not a fourth primary module. Use shared `SpatialObservationPoint`, `PhotoObservation` and `Attachment` UUID relationships, as defined in the [domain model](data-model.md). Multiple photographs may document one point, interval or geological observation without duplicating the image or defining identity by its name/filename.

Target workflow:

1. Open a mining project.
2. Select an excavation and mapping interval.
3. Open its excavation plan, when available.
4. Place or select an observation point; retain its manually declared location and provenance.
5. Capture one or more photographs with the iPhone camera, or import from Photos/Files.
6. Automatically link the captured/imported photos to the selected point and its consistent project/excavation/interval context. Freeze that context when capture starts so later selection changes cannot relink a pending photo silently.
7. Save the point, photo UUIDs, capture timestamps and coordinates/chainage where known. Missing coordinates must not prevent saving.
8. Add editable photo names, numbers, descriptions and optional categories: roof, left wall, right wall, face, joint, fault, general condition or other.
9. Review thumbnails and full-screen images from the mapping interval or plan point, and navigate between a photograph and its point on the plan.
10. Export the photographs and their register/manifest offline to a workstation.

This workflow also works **without a plan or without georeferencing**: create a named point under the excavation, optionally assign an interval/chainage, retain an unlocated plan mark if available, or enter explicit coordinates manually. Photos can also be linked directly to the project/excavation and optional interval/geological observation without a point. Disable only coordinate derivation or plan navigation when their prerequisites are absent, not capture, review or export. Unknown X/Y/Z remain unknown; a plan-selected coordinate is not a surveyed coordinate and underground GPS is not assumed.

Preserve original images whenever practical in offline managed storage; thumbnails and display/export derivatives are separate attachments. Record capture versus import time, source, actual format/dimensions/hash and any original-unavailable/transcoding limitation. Optional viewing direction records its north reference and provenance; it is not inferred from the phone's screen-plane dip direction or copied blindly from EXIF. Retain relevant metadata privately without unnecessarily exposing personal EXIF location data, and never treat EXIF GPS as an underground survey position. Editing names/descriptions does not modify original image bytes or remove evidence history.

The planned workstation export is a ZIP containing originals in its reviewed original-image profile, an XLSX photograph register, a machine-readable manifest and optional CSV register, with stable UUID-based relative paths. Unknown-coordinate records remain exportable. Report missing/damaged attachments and preserve their records; include all referenced originals and required metadata in complete offline backups. Privacy-reviewed sanitized export copies must be identified as derivatives, never silently presented as byte-identical originals. See [storage and recovery](architecture.md) and [photo export specification](import-export.md). No camera workflow, photo database or XLSX generator is implemented in this PR.

## 2. Excavation Plans & Spatial Positioning

### Plan and location workflow

An engineer must be able to import and open prepared **PDF and raster excavation plans** offline, use **DXF-derived survey geometry** through a suitable adapter or desktop preprocessing workflow, and configure local mine coordinates, CRS and units. Retain original plan assets and their version/provenance.

Required operations:

1. Georeference a raster plan using surveyed control points and a documented transformation model, axis/unit conventions, residuals and validity extent. Plan placement alone does not establish a surveyed datum.
2. Select an observation location manually on the plan. Calculate coordinates only when its georeferencing and source metadata are valid for that position; otherwise retain an unlocated plan mark or explicitly approximate location.
3. Enter **X, Y, Z** manually with the selected coordinate system and units. A 2D plan does not supply Z unless an explicit elevation source or justified assumption is attached; otherwise Z remains unknown.
4. Associate observations/intervals with chainage and versioned survey alignment, show saved locations and mapped intervals, and select an interval directly from the plan.
5. Retain original and derived locations with stable relationships so plan selection opens the same mapping record rather than a duplicate journal.

**Underground GPS positioning must not be assumed.** Location is established manually using surveyed reference points, chainage, recognizable excavation features and available survey geometry. FieldForge must never imply that the iPhone automatically determined its underground position. A plan tap is a user's declared position, not live device tracking.

Distinguish surveyed coordinates, coordinates derived from a georeferenced plan, manually entered coordinates, and unknown/approximate locations. Provenance and quality are separate: a manual entry may cite a surveyed source, and a transformed plan point may still be approximate. Show the source and uncertainty/limitations rather than collapsing these into “precise location.”

All spatial transformations preserve source/target CRS, units, axes/handedness, survey alignment version, chainage origin/direction and transformation provenance. Keep original coordinates, control points and immutable transformation revisions; later survey/plan changes must not silently move existing observations. North references for joints and excavation axes must be compatible or explicitly converted with documented provenance before common-frame analysis.

### Scope

Desktop preprocessing of CAD and large geometry is acceptable. Direct DWG editing and a complete CAD engine are outside scope; any DWG-derived source requires a suitable licensed or converted workflow. STL/OBJ and other large-mesh support are optional extensions, not primary requirements or prerequisites for plan positioning or wedge visualization. Wedge diagrams can use generated local excavation geometry without a whole-mine model.

## 3. Wedge Analysis

### Purpose and inputs

Provide a compact preliminary engineering workflow for wedges around underground excavations, with an independently documented implementation. Do not copy proprietary software implementations or present FieldForge as a replacement for comprehensive stability software.

The engineer supplies or explicitly selects:

- Excavation-axis azimuth, north reference and inclination where applicable.
- Cross-section type and dimensions with declared units and geometric assumptions.
- Joint-set orientations from mapping or manual inputs, each with source revision, north and direction conventions.
- **Joint cohesion and friction angle** as planned mechanical inputs, with units, source/test/reference and missing-data state.
- Additional geometry or mechanical parameters only where required by the selected verified method, with their assumptions and provenance.

Load shared excavation/joint data by ID rather than retyping it. Do not infer an axis, dimensions, strength parameter or missing reference from an image or a set identifier. Selecting an interval supplies available evidence; absent inputs remain explicit.

### Separate geometric and mechanical results

| Result | Intended capability | Limit |
| --- | --- | --- |
| Geometric / kinematic feasibility | Represent excavation surfaces and discontinuity orientations; identify candidate plane/surface intersections and geometrically/kinematically feasible configurations under a documented method | A candidate is not proof of actual finite block size, release or instability |
| Mechanical assessment | Account for cohesion and friction using the owner's supplied and verified formulation, plus every additional input required by that method | Unavailable until methodology, applicability, references and engineering tests are established |

Classify relevant configurations as roof-related or wall-related, visualize candidates in clear local 3D or sections, and show input revisions, calculation assumptions, missing information and applicable limitations. Visualization must distinguish bounded candidates from schematic/unbounded intersections; do not draw an assumed finite solid as a measured wedge.

Joint orientations and excavation geometry alone may not determine actual finite wedge volume or release conditions. Depending on the chosen method and case, plane positions/offsets, discontinuity persistence/termination, bounding/free surfaces, excavation extent and release constraints may be required. Record the geometric assumptions or missing inputs and mark indeterminate cases. A direction-only input must not produce a fabricated finite volume. Qualify kinematic findings only for the explicit geometric/release model used.

### Mechanical methodology gate

**The project owner will provide the required engineering formulas and calculation methodology in a later phase.** Cohesion and friction remain planned model inputs until that method is supplied and verified. Design geometry and mechanics as separate services/results; implementing geometry later does not unlock arbitrary stability rules.

Before mechanical implementation, review the owner's formulation, its published references/version and applicability, required inputs/units, sign conventions, missing-data behavior and independent engineering validation cases. Document discrepancies and resolve them before coding. Owner provision alone does not establish verification. Do not invent equations or empirical coefficients, approximate mechanics with an arbitrary friction rule, label a wedge stable/unstable from geometry alone, fabricate factors of safety or risk thresholds, or claim mechanically reliable evaluation without this validation.

Derived results identify both geometric and mechanical method/implementation versions and may explicitly have **mechanical assessment unavailable**. No wedge engine or mechanical calculation is implemented in Phase 2 or this documentation update.

## Shared database and cross-module workflow

All three modules use one consistent project database, stable UUID relationships and the same offline repository services. The current Phase 2 JSON journal remains the implementation; the [architecture](architecture.md) plans relational storage when mapping workflows require it. “Shared database” means a shared domain/store design across modules and iPhone/iPad, not automatic inter-device synchronization.

Target workflow (future functionality):

1. Open an excavation within a project.
2. Select chainage «ПК 0+005» to «ПК 0+010», stored as numeric 5–10 m under that excavation's documented display/origin policy.
3. Register the observation point manually on its plan, recording location provenance and available georeferencing.
4. Capture original orientations and select/interpret J1, J2 and J3 with links to that evidence.
5. Complete the interval's Barton Q characterization using the selected verified method; retain missing inputs if incomplete.
6. Save the mapping interval and its relationships.
7. Open «Клинья» for the selected interval.
8. Load available excavation geometry and joint-set revisions from the same database; request only missing inputs and explicitly review assumptions.
9. Review candidate configurations and any separately available, verified mechanical assessment.
10. Export to Excel or another engineering tool with IDs, provenance and method versions.

Original observations are immutable evidence unless an explicit controlled correction/revision is recorded, preserving the previous value, reason, author/time and revision links. Interpretations and analyses are derived, versioned records referencing exact input revisions. Changes to source interpretations, geometry or transforms mark previous analyses as historical or needing recalculation; do not silently recompute or overwrite evidence. Analysis-specific overrides create new documented inputs without changing the mapped observation. Future archive/deletion policy must protect evidence referenced by saved analyses; the current Phase 2 journal deletion feature is unchanged and does not yet implement this revision/audit workflow.

## One codebase, native iPhone and future iPad

Share domain models, database/repository design, supported Core Motion/measurement services, geometry, future wedge services, import/export and validation. Validate sensor capability on each device; do not assume all iPads provide identical magnetic sensing. Future iPad support is native and adaptive, not a stretched phone layout.

| iPhone emphasis | iPad emphasis |
| --- | --- |
| One-handed capture, quick interval entry, fast manual/sensor observations | Sidebar navigation and split-view mapping |
| Simple plan navigation and compact candidate visualization | Larger plans, simultaneous plan/forms and expanded wedge visualization |
| Large touch targets and short field interactions | Convenient annotation/editing, optional Apple Pencil |

Use reusable feature components, standard SwiftUI size classes and `NavigationSplitView` where appropriate; respond to actual window size/orientation rather than device name alone. Keep shared state, validations, selected project/interval and calculation services outside layout-specific views. Project selection/settings remain secondary. Apple Pencil is optional and touch workflows must remain complete. The current iPhone target, deployment settings and TabView are not changed by this planning document; no iPad-specific implementation is introduced here.

## UI/UX direction

Aim for a premium modern native iOS experience: clean SwiftUI layouts, graphite/dark neutral surfaces, restrained cyan/teal accents, excellent typography and strong information hierarchy, with legible light and dark themes. Use native interactions, accessible large touch targets suitable for field conditions, clear engineering diagrams and minimal unnecessary animation.

Prioritize speed, legibility and engineering correctness. Show source/reference, missing values and calculation assumptions where they affect decisions; avoid complex nested forms for routine captures. Do not use excessive neon glow, decorative sci-fi effects, irrelevant metric dashboards or visual clutter. Status must be understandable through text/symbols as well as color. Future primary navigation is «Картирование / План / Клинья»; current Phase 2 screens do not require redesign now.

## Explicit exclusions

FieldForge must not expand into full geological 3D modeling, block modeling, complete CAD drawing/editing, general-purpose GIS, finite-element geomechanical simulation, complex mine scheduling, enterprise cloud infrastructure, social networking or unnecessary AI assistants. It is not a complete replacement for Leapfrog, AutoCAD, RS3 or Rocscience UnWedge. Local excavation/wedge diagrams serve the three modules; whole-mine modeling is not a product objective.

## Status and decisions still required

Phase 1/2 provide the observation, journal, CSV and migration foundation; project mapping with photo documentation, prepared plans/positioning, wedge analysis, XLSX and native iPad workflows are future requirements. Existing iOS verification gaps and physical measurement limitations remain documented; the owner schedules application verification after merging PR #3 as described in [finalization](pr3-finalization.md). This vision introduces no application, schema, algorithm, dependency or build-setting changes.

Before the relevant implementation phase, settle the owner's wedge formulation and reference/validation package, supported cross-section and finite-wedge assumptions, strength-input units and applicability, surveyed plan/alignment fixtures and georeferencing acceptance criteria, and minimum native iPad workflow/device capabilities. These open decisions refine implementation; they do not expand the three-module scope or permit invented mechanics.
