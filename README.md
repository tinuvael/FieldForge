# FieldForge

Native, offline iOS application for geological field observations. Swift/SwiftUI, iOS 17+, Russian UI, English code and engineering documentation. No accounts, backend or third-party runtime dependencies.

**Geological measurement accuracy has not been validated.** Display resolution is not accuracy. Simulator observations remain permanently labeled DEMO.

## Product direction (future capabilities)

The [product vision](docs/product-vision.md) defines FieldForge as a professional offline field instrument with exactly three primary modules sharing one project database: **Geomechanical Mapping**, **Excavation Plans & Spatial Positioning**, and **Wedge Analysis**. Target navigation is «Картирование / План / Клинья»; project selection and settings are secondary. The current Phase 2 tabs and working features below remain the implementation status.

Prepared PDF/raster plans and DXF-derived survey geometry will support manual positioning with explicit surveyed/plan-derived/manual/approximate/unknown provenance; underground GPS or automatic phone location is not assumed. Wedge geometry and mechanical assessment are separate: mechanical calculations await owner-provided formulas, verified references and engineering tests. Geometry alone cannot establish stability or a finite wedge volume.

Future native iPad support shares models, storage and engineering services with iPhone through adaptive SwiftUI layouts. Full CAD/GIS/geological modeling, numerical simulation and DWG editing are outside scope; STL/OBJ support is optional. No plan, wedge or iPad feature is implemented by this documentation alignment.

## Working features

- Measurement, journal and settings tabs, native light/dark appearance and portrait/landscape layouts.
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

1. Open «Измерение» and select «Геологический компас».
2. Enter dip and direction, select the recorded north type and optionally add notes. For 0° leave direction blank; for 90° confirm a conventional side if entering one.
3. Check the validation message and normalized preview, then tap «Сохранить». The same unchanged draft cannot be saved twice; «Новое измерение» starts another capture.
4. Open «Журнал» to inspect the original input, source and north. «Настройки → Экспортировать CSV» exports all journal records.

Switching to manual stops acquisition; returning to automatic retains an existing HOLD snapshot. The automatic workflow remains HOLD → optional notes → SAVE → «Продолжить». Simulator presets and DEMO labels apply to automatic observations only.

## Data safety and export

Keep bundle identifier **`com.tinuvael.FieldForge`** and upgrade in place. Do not uninstall/reset the deployed app or change its identifier to test this release. App removal deletes sandbox data.

The active journal stays at Application Support/FieldForge/`measurements-v1.json`. Phase 2 introduces schema **2** while retaining this path. Migration preserves UUIDs, timestamps, orientations, raw diagnostics and notes. It validates all records and a v2 round trip, creates/verifies `measurements-v1.json.phase1-backup`, then replaces the active file atomically. Load, unknown-version, invalid-record or backup failures block writes and preserve the source. A conflicting backup requires explicit recovery; no automatic reset/rollback is performed. See [migration and recovery](docs/persistence-migration.md). Phase 1 cannot read v2; downgrade requires a reviewed recovery plan.

CSV uses UTF-8 BOM, comma separators, CRLF records, UTC ISO 8601 timestamps, round-trip numeric precision and empty cells for missing data. The first 24 Phase 1 column names/order are retained; four provenance/original-input columns are appended. Manual diagnostic cells are blank. Spreadsheet-formula-like text is protected. Consumers must accept additional columns/new enums and full-precision numeric formatting. Use Excel's UTF-8/comma/decimal-dot import when regional detection differs. Excel numeric precision may still reduce values; CSV is not a complete JSON/attachment backup.

The small journal is currently rewritten as atomic JSON. SQLite is recommended when relational interval mapping is implemented; no speculative database or XLSX dependency is added now.

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

Set `DEVELOPER_DIR` to a supported Xcode installation when necessary. Project generation uses Python 3 only, is deterministic and preserves signing/identifier/deployment settings. Core sources run independently via Swift Package Manager; UI and Core Motion require Apple SDKs. Debug UI tests use `ui-testing.json`, never the deployed journal.

```text
FieldForge/App/                  composition, lifecycle, automatic session and manual draft
FieldForge/Core/Geometry/        sensor-independent orientation, coordinates and conventions
FieldForge/Core/Sensors/         diagnostic values, Core Motion and mock adapters
FieldForge/Data/Models/          observation provenance, validation and HOLD
FieldForge/Data/Storage/         versioned JSON, migration, backup and integrity protection
FieldForge/Features/             Russian SwiftUI measurement, journal and settings
FieldForge/Services/Export/      CSV and temporary export file
Tests/                          geometry, automatic/manual observation, migration and CSV XCTest
UITests/                        automatic and manual save/relaunch/export workflows
scripts/generate_project.py     deterministic checked-in Xcode project
```

Phase 2 core verification: **70 XCTest tests passed on Linux with Swift 6.0.3**. Xcode/simulator and UI tests are unavailable in the current Linux environment and remain pending; prior Phase 1 Apple build results do not verify this change. Full details: [Phase 2 verification](docs/phase2-verification.md), [historical Phase 1 verification](docs/verification.md).

## Architecture and next steps

See the authoritative [product vision](docs/product-vision.md), [development rules](AGENTS.md), [architecture and persistence decision](docs/architecture.md), [future shared domain schema](docs/data-model.md), [coordinates](docs/coordinate-systems.md), [export and prepared-plan boundaries](docs/import-export.md), and [roadmap](docs/roadmap.md).

The immediate next step is simulator verification and a backed-up in-place upgrade check on the physical iPhone. Then develop interval mapping, prepared-plan positioning and preliminary wedge analysis through separate verified phases, with native iPad adaptation planned from the shared codebase. Q/RMR, XLSX, spatial transforms and wedge calculations remain future work; mechanical wedge implementation depends on the owner's verified methodology. A whole-mine 3D viewer is not a primary product goal.
