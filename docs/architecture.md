# Architecture foundation (Phase 2)

## Product boundaries

The authoritative [product vision](product-vision.md) defines exactly three primary modules: **Geomechanical Mapping**, **Excavation Plans & Spatial Positioning**, and **Wedge Analysis**. All use one consistent offline project database, stable IDs and common engineering services. Measurement, exports and backups serve those modules rather than becoming independent products. Current Phase 2 functionality below is unchanged; the following future service boundaries do not implement additional features.

## Current implementation

FieldForge is a native Swift/SwiftUI, iOS 17+, Russian-language, offline application. It has no runtime third-party dependency, backend, account, or network requirement. `AppModel` composes a sensor provider, HOLD session, manual draft, shared journal store, and export service on the main actor.

```mermaid
flowchart LR
    CM[Core Motion adapter] --> SS[SensorSample diagnostics]
    Mock[Simulator adapter] --> SS
    SS --> Processing[Phase 1 geometry and quality rules]
    Processing --> Observation[Measurement observation]
    Manual[ManualOrientationInput validation] --> Observation
    Observation --> Journal[Shared journal and details]
    Observation --> Store[MeasurementStore / versioned JSON]
    Journal --> CSV[CSVExporter / native Share Sheet]
```

- `Core/Geometry`: Foundation-only vectors, orientation values, north and direction conventions. No Core Motion or UI dependency. Phase 1 geometry remains unchanged.
- `Core/Sensors`: immutable-by-snapshot diagnostic values and adapters. Core Motion retains its 20 Hz acquisition, magnetic calibration/field guards, motion checks, generation tokens, and freshness watchdog.
- `Data/Models`: provenance-aware `Measurement`, manual input validation, and sensor HOLD state. Manual observations do not pass through `MeasurementSession` or invent samples.
- `Data/Storage`: explicit v1 reader, v2 envelope, record validation, non-overwriting legacy backup, atomic replacement, and write protection.
- `Services/Export`: CSV transport encoding separated from UI formatting.
- `Features`: SwiftUI presentation with Russian labels. Both sources use the same journal and exporter.

`Measurement` is an original orientation observation, not a statistical joint set. Its `PlaneOrientation` has no sensor dependency. The optional `sample` contains diagnostics only when the source is `iPhoneSensor` or `simulatorMock`; validation requires a consistent source/sample pair. Manual records require validated original input, `manualUnverified` quality, and `manual-entry-v1`. Unsupported external-instrument records cannot yet be saved. North metadata and user notes belong to the observation, not to Core Motion.

Manual input is validated continuously; SAVE is enabled only for valid input and writable storage. Saving the same draft twice is disabled. Editing creates a new unsaved draft; «Новое измерение» clears it explicitly. Each capture gets a UUID; the store rejects duplicate UUIDs, while repeated observations of the same angle remain legitimate. Switching to manual stops acquisition and preserves any sensor HOLD snapshot; returning to automatic resumes the existing HOLD workflow. Background/tab lifecycle rules still apply.

## Future domain boundaries

The [domain schema](data-model.md) defines projects, excavations, intervals, rock-mass assessments, interpretations, original measurements, prepared plans/locations, and versioned analysis inputs/results. These are a design contract, not implemented screens or database entities in Phase 2. Add capabilities when their workflow is ready, rather than implementing a generic framework now.

Future services should accept domain values/IDs: classification services consume versioned interval assessment inputs, interpretation services create explicit joint-set representatives with links to originals, spatial services resolve manually selected plan/alignment positions into declared model coordinate systems, and exporters read a consistent repository snapshot. None should mutate original observation values as a side effect. Original evidence uses controlled correction revisions; representative orientations, location transforms and analysis results reference exact input versions.

| Primary module | Future service boundary / shared data |
| --- | --- |
| Geomechanical Mapping | Interval capture, original observations, explicit interpretations and versioned Q/RMR characterization |
| Excavation Plans & Spatial Positioning | Prepared PDF/raster/DXF-derived assets, surveyed controls, georeferencing revisions, manual X/Y/Z and chainage selection, provenance-aware location records |
| Wedge Analysis | Input selection by excavation/interval and joint-set revision IDs, separate geometric/kinematic candidates and mechanical assessment, local candidate visualization |

Plan location selection opens the same mapping interval by ID. Wedge input assembly reads its saved excavation geometry and interpreted sets, reports missing values and records overrides as analysis-specific inputs; it never creates another measurement journal. A 2D plan point does not imply elevation or automatic underground position. Spatial services preserve CRS/units/axes, alignment version and chainage origin/direction.

### Wedge service separation (future)

Keep geometric/kinematic candidate generation independent of mechanical assessment. Geometry consumes explicitly versioned excavation surfaces and discontinuity inputs, reports intersections/configurations and missing bounds or release assumptions, and may return indeterminate/unbounded results. Visualization consumes that geometry; it does not decide stability. Joint orientations alone are insufficient to assert finite wedge volume.

Mechanical assessment consumes a geometry result plus a separately validated mechanical input snapshot. Cohesion and friction angle are planned inputs, with units/source and unknown states; any other parameter must be justified by the selected method. **Owner-provided formulas/methodology, verified published references and independent engineering cases/tests are required before implementing mechanics.** No arbitrary friction rules, stable/unstable labels, factors of safety or risk thresholds may be inferred from geometry. Persist geometric and mechanical method/implementation versions separately, including an explicit unavailable mechanical result. No wedge engine is added in this PR.

### Native iPhone / future iPad codebase

Share domain models, repository/database design, capability-checked measurement providers, validation, geometry, future wedge services and import/export. A shared database design does not imply device synchronization. Keep selected project/interval, capture state and engineering computations separate from device-specific layouts. Use size classes/window size, reusable SwiftUI components and `NavigationSplitView` where appropriate: compact one-handed iPhone capture versus iPad sidebar/split-view plan/forms, expanded candidate views and optional Pencil annotation. Do not assume identical sensor capabilities or stretch the phone layout. No iPad target, deployment change or current TabView redesign is introduced here.

Local plan and wedge display are the spatial UI priorities. Complete CAD/DWG editing, general-purpose GIS, full 3D geological/mine modeling and numerical geomechanical simulation remain outside scope. Large imported meshes are optional extensions, not a prerequisite for the three modules; see [import/export](import-export.md).

## Persistence decision and migration path

Keep the current `MeasurementStore` and JSON journal for this phase. Whole-file rewrite and in-memory lists are reasonable at prototype scale, but unsuitable for projects with thousands of intervals, photographs, and geometry. Do not store image/mesh bytes inline in record JSON.

| Option | Strengths | Constraints for FieldForge |
| --- | --- | --- |
| SwiftData (iOS 17+) | Native Swift relationship/query integration, minimal setup | Migration behavior and store portability need qualification; framework model coupling and backup recovery require care; no implicit cloud sync should be enabled |
| SQLite via system SQLite3 | Explicit foreign keys, indexed queries, transactions, versioned SQL migrations, portable inspectable backups | Requires typed mapping and disciplined connection/transaction ownership |
| JSON repository | Human-readable, simple, current deployed compatibility | Rewrites all records; no foreign keys or efficient interval queries; relationships must be validated manually |

**Recommend SQLite when the mapping workflow is implemented**, using the system library first and a small repository interface shaped by actual queries. Evaluate a maintained wrapper only if it demonstrably simplifies correctness. Do not add it in this PR. Use `PRAGMA foreign_keys=ON` on every connection, indexed parent IDs/chainage/timestamps, explicit schema history, transactional migrations, integrity checks, and a serialized writer. Keep query/DTO boundaries independent of SwiftUI and Core Motion. Prefer restrictive relationship deletion until the user explicitly chooses a reviewed cascade/archive operation.

Planned JSON → SQLite transition:

1. Read and validate the complete existing JSON through the current migration reader; retain original bytes and IDs.
2. Create a new staging database. Insert original observations and provenance in one transaction; standalone journal records have nullable interval links.
3. Verify counts, UUID sets, timestamps, exact orientation/diagnostic values, constraints, and export round trips. Do not infer project/interval membership.
4. Atomically promote the validated database with an explicit migration marker. Retain JSON and recovery instructions. Do not delete the only readable source.
5. Back up using SQLite's online backup API or a consistent closed snapshot, including attachments and a manifest. Never copy only the live WAL database file. Restore into staging and validate before activation.

Keep photos and large geometry in an application-managed attachment directory, referenced by UUID, content hash, size, media type, and relative path. Coordinate record/attachment transactions through staging and a manifest, recover interrupted imports, and garbage-collect only after reference checks. Backups must include all referenced attachments; XLSX/CSV are analysis outputs, not complete backups.

See [current safe migration](persistence-migration.md), [coordinate systems](coordinate-systems.md), and [import/export boundaries](import-export.md).
