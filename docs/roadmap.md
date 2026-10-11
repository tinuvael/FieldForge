# Development roadmap

## Phase 1 — merged foundation

Native measurement/journal/settings tabs; independent screen-plane geometry; sensor diagnostics and quality gates; HOLD/SAVE; simulator source; offline JSON and CSV. Physical iPhone 15 Pro Max/iOS 27 startup, sensor acquisition and one saved observation have been reported by the project owner. Geological accuracy and long-term reliability remain unverified.

## Phase 2 — this change

Provenance-aware observations, manual compass entry, explicit north and vertical conventions, preserved original inputs, shared journal/CSV, safe v1→v2 migration and engineering/domain/export documentation. No Q/RMR calculations, mapping UI, CAD parser, XLSX generation, spatial viewer, backend or cloud sync.

## Next: qualify the upgrade and field workflow

Run Xcode simulator build plus all unit/UI tests, then a signed **in-place upgrade** on the deployed iPhone after preserving a copy of the current journal. Verify UUIDs/timestamps/notes/diagnostics and a mixed manual/sensor CSV. Do not uninstall/reset the app or change its bundle ID. Exercise HOLD across modes/tabs/backgrounding and decimal-comma/manual horizontal/vertical inputs. Test storage failure recovery on test copies, never the only production journal.

In parallel with subsequent software design, execute controlled geological-compass/inclinometer comparisons following [measurement-geometry.md](measurement-geometry.md): frame convention, repeatability, bias, fixture alignment, heading dependence and magnetic interference. Define acceptance criteria before interpreting accuracy. Physical startup is not sensor calibration or operational qualification.

## Next mapping phase

Implement project/excavation/interval workflow with numeric chainage, interval-level descriptions/photos, explicitly interpreted J1–J5 and unrestricted tectonic records. Adopt SQLite only as relational workflow/query needs materialize; test JSON migration and complete attachment backup first. Preserve standalone observations and incomplete intervals. No automatic clustering of five observations into five sets.

## Later verified classifications and exports

Select and verify specific published Q/RMR methods/versions with reference tables, independent worked examples, missing-input handling and boundary tests before adding calculations. Then implement versioned structured backups and multi-table CSV, qualified DIPS tables and XLSX with stable IDs and no loss of incomplete parent rows.

## Later survey / CAD / 3D

Versioned alignment metadata and tested interpolation; explicit CRS/mine grid/unit transforms; desktop preprocessing and prepared mobile assets; bounded model queries/rendering. Qualify each supported format/framework/OS independently. DWG requires a suitable licensed or converted workflow; STL requires explicit spatial metadata. Cloud synchronization, if ever requested, follows reliable local persistence/backups and a reviewed conflict model.
