# FieldForge

Native, offline iOS application for geological field observations. Swift/SwiftUI, iOS 17+, Russian UI, English code and engineering documentation. No accounts, backend or third-party runtime dependencies.

**Geological measurement accuracy has not been validated.** Display resolution is not accuracy. Simulator observations remain permanently labeled DEMO.

## Product direction (future capabilities)

The [product vision](docs/product-vision.md) defines FieldForge as a professional offline field instrument with exactly three primary modules sharing one project database: **Geomechanical Mapping**, **Excavation Plans & Spatial Positioning**, and **Wedge Analysis**. Target navigation is «Картирование / План / Клинья»; project selection and settings are secondary. P1 implements the mapping foundation described below; the plan and wedge tabs are explicit placeholders.

Prepared PDF/raster plans and DXF-derived survey geometry will support manual positioning with explicit surveyed/plan-derived/manual/approximate/unknown provenance; underground GPS or automatic phone location is not assumed. Wedge geometry and mechanical assessment are separate: mechanical calculations await owner-provided formulas, verified references and engineering tests. Geometry alone cannot establish stability or a finite wedge volume.

Future native iPad support shares models, storage and engineering services with iPhone through adaptive SwiftUI layouts. Full CAD/GIS/geological modeling, numerical simulation and DWG editing are outside scope; STL/OBJ support is optional. No plan, wedge or iPad feature is implemented by this documentation alignment.

Photo documentation is a core **future** Mapping/Plan workflow: named observation points, multiple camera/imported photos, explicit location provenance, offline originals/thumbnails and workstation ZIP packages with a photograph register and manifest. It also works without georeferenced plans or coordinates. No photo capture, database or XLSX functionality is implemented yet; see the [product vision](docs/product-vision.md).

## Working features

- Main tabs «Картирование / План / Клинья»; mapping has a fixed project/horizon/excavation context panel, project journal and secondary measurement/settings navigation. Plan and wedge functionality is visibly unavailable.
- Create/rename projects, create/edit horizons with optional elevation metadata, and manage one excavation across multiple horizons. Context persists between sessions.
- Save consecutive individual picket observations with numeric meters, original field date/timezone, optional manual X/Y/Z with explicit provenance and notes. Success clears the draft and retains context; failed validation/storage and cancelled context switching preserve it.
- Project-filtered journal with date/picket sorting and read-only original observations. Full relationships are validated in atomic versioned JSON commits with a previous-snapshot backup. See [P1 workflow/storage](docs/p1-mapping.md).
- Automatic screen-plane measurements using Core Motion: dip angle, nullable dip direction, magnetic/motion diagnostics and quality checks; HOLD freezes a complete observation, SAVE stores it once.
- Manual geological-compass entry: dip angle 0–90°, dip direction 0–360°, magnetic/true/grid/unknown north and optional notes. Decimal comma/dot is accepted, validation is shown before saving, and 360° is stored as 0° with original input retained.
- Horizontal manual planes require an undefined direction (blank field). Vertical manual planes permit blank direction or an explicitly confirmed conventional dip side. The latter is labeled as a convention.
- A shared offline journal for manual, iPhone and simulator observations, details, original notes/inputs, source labels and deletion. Manual records contain no artificial sensor samples.
- CSV export through the native Share Sheet, including source, north, direction meaning and mixed observation types.
- Automatic, validated migration of deployed Phase 1 JSON records with an exact original backup and failure protection.

No conversion between magnetic, true and grid north is performed. Core Motion still uses magnetic north where its existing quality gates permit it; otherwise only dip is available. The automatic 0.5° singularity guard remains unchanged. Manual measurements near 0°/90° retain the entered values independently of that sensor guard.

## Physical verification status

The project owner reports a successful installation and launch on **iPhone 15 Pro Max running iOS 27**, observed real Core Motion readings, and a measurement saved to the journal. These establish physical startup, sensor acquisition and basic persistence for Phase 1.

They do **not** establish geological compass accuracy, repeatability, long-term reliability, magnetic interference rejection or Phase 2 upgrade behavior. High magnetometer calibration does not exclude local steel/rock/electrical interference. Controlled comparison with independent instruments and a validated phone fixture remains required; see the [physical validation procedure](docs/measurement-geometry.md).

## Manual workflow

1. Open «Картирование → Сервисы → Измерение» and select «Геологический компас».
2. Enter dip and direction, select the recorded north type and optionally add notes. For 0° leave direction blank; for 90° confirm a conventional side if entering one.
3. Check the validation message and normalized preview, then tap «Сохранить». The same unchanged draft cannot be saved twice; «Новое измерение» starts another capture.
4. Open «Картирование → Сервисы → Неназначенные измерения» to inspect originals. «Сервисы → Настройки → Экспортировать CSV» exports the standalone measurements (mapping export is deferred).

Switching to manual stops acquisition; returning to automatic retains an existing HOLD snapshot. The automatic workflow remains HOLD → optional notes → SAVE → «Продолжить». Simulator presets and DEMO labels apply to automatic observations only.

## Data safety and export

Keep bundle identifier **`com.tinuvael.FieldForge`** and upgrade in place. Do not uninstall/reset the deployed app or change its identifier to test this release. App removal deletes sandbox data.

The active journal stays at Application Support/FieldForge/`measurements-v1.json`. Phase 2 introduces schema **2** while retaining this path. Migration preserves UUIDs, timestamps, orientations, raw diagnostics and notes. It validates all records and a v2 round trip, creates/verifies `measurements-v1.json.phase1-backup`, then replaces the active file atomically. Load, unknown-version, invalid-record or backup failures block writes and preserve the source. A conflicting backup requires explicit recovery; no automatic reset/rollback is performed. See [migration and recovery](docs/persistence-migration.md). Phase 1 cannot read v2; downgrade requires a reviewed recovery plan.

CSV uses UTF-8 BOM, comma separators, CRLF records, UTC ISO 8601 timestamps, round-trip numeric precision and empty cells for missing data. The first 24 Phase 1 column names/order are retained; four provenance/original-input columns are appended. Manual diagnostic cells are blank. Spreadsheet-formula-like text is protected. Consumers must accept additional columns/new enums and full-precision numeric formatting. Use Excel's UTF-8/comma/decimal-dot import when regional detection differs. Excel numeric precision may still reduce values; CSV is not a complete JSON/attachment backup.

The project graph uses `mapping-v1.json` (schema 1), isolated from the protected standalone measurement journal. It is atomically rewritten as one validated aggregate; `mapping-v1.json.previous` retains the prior snapshot. No legacy assignment/migration is guessed. SQLite remains the next storage step before large plan/attachment workloads; see the [P1 storage decision](docs/p1-mapping.md).

## Development

Open `FieldForge.xcodeproj`, select the shared **FieldForge** scheme and an installed iPhone simulator. Run with ⌘R, test with ⌘U. On a physical phone select your Team locally with automatic signing and retain the existing identifier. Never commit signing assets or device data. Deployment/debugging requires a toolchain that supports the selected device OS; simulator builds do not prove physical compatibility.

```sh
python3 scripts/generate_project.py
swift test
xcrun simctl list devices available
xcodebuild -project FieldForge.xcodeproj -scheme FieldForge \
  -destination 'platform=iOS Simulator,id=<available-device-UUID>' \
  -derivedDataPath /tmp/FieldForge-DerivedData CODE_SIGNING_ALLOWED=NO build
xcodebuild -project FieldForge.xcodeproj -scheme FieldForge \
  -destination 'platform=iOS Simulator,id=<available-device-UUID>' \
  -derivedDataPath /tmp/FieldForge-DerivedData CODE_SIGNING_ALLOWED=NO test
```

Set `DEVELOPER_DIR` to a supported Xcode installation when necessary. Project generation uses Python 3 only and is deterministic. Machine-local signing overrides belong in ignored `Config/LocalSigning.xcconfig` (`DEVELOPMENT_TEAM = your Team`), optionally included by `Config/Signing.xcconfig`; they survive regeneration. Identifier and deployment settings remain unchanged. Core sources run independently via Swift Package Manager; UI and Core Motion require Apple SDKs. Debug UI tests use `ui-testing.json` and `ui-testing-mapping.json`, never the deployed journals.

```text
FieldForge/App/                  composition, lifecycle, automatic session and manual draft
FieldForge/Core/Geometry/        sensor-independent orientation, coordinates and conventions
FieldForge/Core/Sensors/         diagnostic values, Core Motion and mock adapters
FieldForge/Data/Models/          project graph, mapping draft, observation provenance, validation and HOLD
FieldForge/Data/Storage/         versioned JSON, migration, backup and integrity protection
FieldForge/Features/             Russian SwiftUI mapping/context, measurement, journals and settings
FieldForge/Services/Export/      CSV and temporary export file
Tests/                          mapping/reset/context/integrity, geometry, observations, migration and CSV XCTest
UITests/                        mapping acceptance and automatic/manual save/relaunch/export workflows
scripts/generate_project.py     deterministic checked-in Xcode project
```

Current P1 verification: see [executed tests and limitations](docs/p1-verification.md). Earlier Phase 1/2 verification reports are historical. Physical measurement accuracy and device upgrade behavior still require owner validation.

## Architecture and next steps

See the authoritative [product vision](docs/product-vision.md), [development rules](AGENTS.md), [architecture and persistence decision](docs/architecture.md), [future shared domain schema](docs/data-model.md), [coordinates](docs/coordinate-systems.md), [export and prepared-plan boundaries](docs/import-export.md), and [roadmap](docs/roadmap.md).

P1 supplies individual mapping points and a project-aware journal. Original measurement capture/linking inside mapping is deferred to Issue #8; interval revisions, photo documentation, prepared-plan positioning and wedge analysis follow separately, with native iPad adaptation planned from the shared codebase. Q/RMR, XLSX, spatial transforms and wedge calculations remain future work; mechanical wedge implementation depends on the owner's verified methodology. A whole-mine 3D viewer is not a primary product goal.
