# Development roadmap

The authoritative [product vision](product-vision.md) defines exactly three primary modules: **Geomechanical Mapping**, **Excavation Plans & Spatial Positioning**, and **Wedge Analysis**, sharing one offline project database. This roadmap sequences their implementation and future native iPad adaptation; it does not add a CAD/GIS/geological-modeling or numerical-simulation product. Existing Phase 1/2 features and verification remain distinct from future milestones.

## Phase 1 — merged foundation

Native measurement/journal/settings tabs; independent screen-plane geometry; sensor diagnostics and quality gates; HOLD/SAVE; simulator source; offline JSON and CSV. Physical iPhone 15 Pro Max/iOS 27 startup, sensor acquisition and one saved observation have been reported by the project owner. Geological accuracy and long-term reliability remain unverified.

## Phase 2 — this change

Provenance-aware observations, manual compass entry, explicit north and vertical conventions, preserved original inputs, shared journal/CSV, safe v1→v2 migration and engineering/domain/export documentation. Product vision and shared-module/iPad architecture are documentation only. No Q/RMR calculations, mapping UI, CAD parser, XLSX generation, plan positioning, wedge engine, iPad target, backend or cloud sync.

## Next: qualify the upgrade and field workflow

Run Xcode simulator build plus all unit/UI tests, then a signed **in-place upgrade** on the deployed iPhone after preserving a copy of the current journal. Verify UUIDs/timestamps/notes/diagnostics and a mixed manual/sensor CSV. Do not uninstall/reset the app or change its bundle ID. Exercise HOLD across modes/tabs/backgrounding and decimal-comma/manual horizontal/vertical inputs. Test storage failure recovery on test copies, never the only production journal.

In parallel with subsequent software design, execute controlled geological-compass/inclinometer comparisons following [measurement-geometry.md](measurement-geometry.md): frame convention, repeatability, bias, fixture alignment, heading dependence and magnetic interference. Define acceptance criteria before interpreting accuracy. Physical startup is not sensor calibration or operational qualification.

## Next mapping phase

Implement project/excavation/interval workflow with numeric chainage, interval-level descriptions/photos, explicitly interpreted J1–J5 and unrestricted tectonic records. Adopt SQLite only as relational workflow/query needs materialize; test JSON migration and complete attachment backup first. Preserve standalone observations and incomplete intervals. No automatic clustering of five observations into five sets.

Add controlled evidence corrections/revisions and versioned representatives so later plan locations and analyses reference exact inputs without overwriting originals. Keep project selection/settings secondary and adopt «Картирование» when that workflow exists, preserving fast sensor/manual capture.

## Later verified classifications and exports

Select and verify specific published Q/RMR methods/versions with reference tables, independent worked examples, missing-input handling and boundary tests before adding calculations. Then implement versioned structured backups and multi-table CSV, qualified DIPS tables and XLSX with stable IDs and no loss of incomplete parent rows.

## Excavation Plans & Spatial Positioning

Implement offline PDF/raster display and a qualified DXF-derived survey/preprocessing workflow; define surveyed fixtures, control-point/georeferencing models and acceptance criteria before coordinate calculation. Support manually selected plan locations and X/Y/Z, explicit surveyed/plan-derived/manual/approximate/unknown provenance, CRS/units/axes and alignment version/chainage origin/direction. Preserve missing elevation and unlocated plan marks. Show and select existing mapped intervals on the plan through the shared database. Underground GPS or automatic device positioning is not assumed.

Versioned alignment metadata and tested interpolation follow actual survey requirements. Desktop preprocessing handles complex CAD assets; no direct DWG editing/full CAD or whole-mine 3D modeling is planned. STL/OBJ/other mesh support remains optional, with explicit metadata and bounded loading if later justified. A generated local wedge diagram does not depend on a large-mesh importer.

## Wedge Analysis — geometry, then verified mechanics

Define excavation axis/north/inclination, cross-section/dimensions, joint-set revision links and geometric bounds/release assumptions. Implement independently documented and tested geometric/kinematic candidate generation with roof/wall context, intersections, explicit insufficient-data states and compact 3D/sectional visualization. Joint orientations alone do not establish finite wedge volume or mechanical stability.

Mechanical assessment is a separate, gated milestone: **the owner must supply the formulas and calculation methodology**, followed by verification of published references/version, applicability, required units/inputs and independent engineering examples/tests. Cohesion and friction are planned inputs until then. Do not substitute arbitrary friction rules, stable/unstable labels, safety factors or risk thresholds for the missing method. Version geometric and mechanical inputs/results separately and retain unavailable assessments. No wedge calculation is implemented in the current PR.

## Native iPad adaptation

Maintain shared domain/database, capability-checked measurement, geometry/wedge, validation and import/export services throughout preceding milestones. Later add native adaptive iPad layouts using reusable SwiftUI components, size classes/window sizes and `NavigationSplitView` where appropriate: sidebar/split plan/forms, expanded wedge visualization and optional Pencil annotation. Preserve one-handed iPhone capture and test each supported device's sensor capabilities. Shared code/storage design does not imply inter-device synchronization. No target or deployment-setting change is part of this documentation task.
