# FieldForge

Native, offline iOS application for geological field observations. Swift/SwiftUI, iOS 17+, Russian UI, English code and engineering documentation. No accounts, backend or third-party runtime dependencies.

**Geological measurement accuracy has not been validated.** Display resolution is not accuracy. Simulator observations remain permanently labeled DEMO.

## Product direction (future capabilities)

The [product vision](docs/product-vision.md) defines FieldForge as a professional offline field instrument with exactly three primary modules sharing one project database: **Geomechanical Mapping**, **Excavation Plans & Spatial Positioning**, and **Wedge Analysis**. Target navigation is «Картирование / План / Клинья»; project selection and settings are secondary. P2 implements mapping, numeric horizons and offline horizon DXF plans; the wedge tab remains an explicit placeholder.

Prepared PDF/raster plans and DXF-derived survey geometry will support manual positioning with explicit surveyed/plan-derived/manual/approximate/unknown provenance; underground GPS or automatic phone location is not assumed. Wedge geometry and mechanical assessment are separate: mechanical calculations await owner-provided formulas, verified references and engineering tests. Geometry alone cannot establish stability or a finite wedge volume.

Future native iPad support shares models, storage and engineering services with iPhone through adaptive SwiftUI layouts. Full CAD/GIS/geological modeling, numerical simulation and DWG editing are outside scope; STL/OBJ support is optional. Native iPad layouts, wedge analysis and raster/PDF georeferencing remain future work.

P4.1 adds multiple camera/Photos/Files photographs to saved Mapping/Plan observations, including points without plans or coordinates. It preserves frozen point revisions, received image bytes, hashes and metadata history with recoverable imports, thumbnails and zoom. Draft-point/point-free photos and workstation XLSX/ZIP packages remain future work; see the [implemented photo contract](docs/p4-1-photos.md).

## Working features

- Saved-point photographs: camera capability/permission handling, multi-image Photos/Files imports, individual names/numbers/descriptions/categories, capture versus import time, immutable metadata history, thumbnails and full-screen pinch zoom. UUID paths and SHA-256 originals stay offline; pending operations resume without duplicate records. Missing/corrupt originals stay visible. See [P4.1 scope, recovery and backup composition](docs/p4-1-photos.md).

- Main tabs «Картирование / План / Клинья»; mapping has a fixed project/horizon/excavation context panel, project journal and secondary measurement/settings navigation. The Plan tab opens imported horizon plans; wedge analysis remains unavailable.
- Create/rename projects, create/edit numeric signed/decimal horizon elevations (preserving legacy names/UUIDs), and manage one excavation across multiple horizons. Context persists between sessions.
- Save consecutive individual picket observations with numeric meters, original field date/timezone, optional X/Y/Z and notes. The compact form automatically records unknown/manual or selected-plan provenance. Horizon elevation suggests nominal Z; manual override/clear is preserved. Success resets per-point data and suggests horizon Z again; failures retain the draft.
- Offline multi-DXF import from Files per horizon, original files with SHA-256, explicit unit/CRS setup, recoverable pending imports, pan/zoom and confirmed XY picking. LINE, straight LWPOLYLINE, 2D/3D POLYLINE in WCS XY projection, ARC/CIRCLE, POINT and bounded plain TEXT/MTEXT display; source 3D vertices and original bytes are retained separately from observation Z; unsupported entities including BLOCK/INSERT are reported. Saved source-plan markers open the same effective journal records, with excavation filtering and overlapping-point selection. See [P2 workflow, DXF subset and data safety](docs/p2-dxf.md).
- Project journal with searchable horizon/excavation selectors, picket/number search, an optional inclusive date period and secondary date/picket sorting; one effective observation per stable UUID, with immutable originals and correction history. Full relationships are validated in atomic versioned JSON commits with a previous-snapshot backup. See [P1 workflow/storage](docs/p1-mapping.md).
- Interpreted J1–J5 systems with explicitly entered orientations/north, optional links to multiple point originals and field descriptions; optional interval bounds/position and arbitrary tectonic structures. All commit atomically with the point, reset on success and reopen in separate journal sections. See [P3.2a geology and validation](docs/p3-2a-geology.md).
- Point/interval Barton Q using verified NGI April 2025 tables: explicit Russian selections and special-case decisions, original/used RQD, validated calculation and seven classes, source/method snapshots and incomplete status. Separate RMR89 input form remains explicitly uncalculated pending complete original-table verification. Both save/reset atomically and reopen in the journal; no support design. See [methodology, tables, acceptance examples and limits](docs/p3-2b-ratings.md).
- Saved observation corrections: «Редактировать наблюдение» prefills effective values; a required reason and optional author create an atomic immutable revision. «История изменений» opens original/prior snapshots and lists changed fields. Journal filters and DXF overlays use one latest point. Original sensor/manual evidence and project/horizon/excavation ownership cannot be changed. Q inputs reuse the NGI 2025 evaluator; RMR89 stays input-only. Failed saves retain the correction draft; Cancel confirms discarding changed drafts. See [P3.3 revision contract](docs/p3-3-revisions.md).
- Tectonic structures can retain complete, partial or unknown orientation without fabricated angles; the journal identifies missing parameters. Left/right walls are defined looking toward increasing picketage, without inferring a geographic direction.
- Integrated point measurements: «Измерить iPhone» opens a native plane-orientation dial with HOLD/retake/add; «Ручной ввод» adds geological compass originals. Multiple mixed readings stay in the draft until one atomic point save; journal details show every original. See [P3.1 capture and storage](docs/p3-measurements.md) and [verification](docs/p3-verification.md).
- Independent automatic screen-plane measurements using Core Motion: dip angle, nullable dip direction, magnetic/motion diagnostics and quality checks; HOLD freezes a complete observation, SAVE stores it once.
- Manual geological-compass entry: dip angle 0–90°, dip direction 0–360°, magnetic/true/grid/unknown north and optional notes. Decimal comma/dot is accepted, validation is shown before saving, and 360° is stored as 0° with original input retained.
- Horizontal manual planes require an undefined direction (blank field). Vertical manual planes permit blank direction or an explicitly confirmed conventional dip side. The latter is labeled as a convention.
- The independent offline journal for manual, iPhone and simulator observations, details, original notes/inputs, source labels and deletion. Manual records contain no artificial sensor samples.
- CSV export through the native Share Sheet, including source, north, direction meaning and mixed observation types.
- Automatic, validated migration of deployed Phase 1 JSON records with an exact original backup and failure protection.

No conversion between magnetic, true and grid north is performed. Core Motion still uses magnetic north where its existing quality gates permit it; otherwise only dip is available. The automatic 0.5° singularity guard remains unchanged. Manual measurements near 0°/90° retain the entered values independently of that sensor guard.

## Physical verification status

The project owner reports a successful installation and launch on **iPhone 15 Pro Max running iOS 27**, observed real Core Motion readings, and a measurement saved to the journal. These establish physical startup, sensor acquisition and basic persistence for Phase 1.

They do **not** establish geological compass accuracy, repeatability, long-term reliability, magnetic interference rejection or Phase 2 upgrade behavior. High magnetometer calibration does not exclude local steel/rock/electrical interference. Controlled comparison with independent instruments and a validated phone fixture remains required; see the [physical validation procedure](docs/measurement-geometry.md).

## Mapping measurement workflow

1. Select Project/Horizon/Excavation and enter the picket.
2. Use «Измерить iPhone → Зафиксировать → Добавить замер» or «Ручной ввод → Добавить замер». Repeat for more originals; all remain unsaved point evidence.
3. Optionally expand «Интервал и положение», «Системы трещин» and «Тектоника». Enter interpreted representatives explicitly, select original evidence links and add structural records. Opening an editor does not save the point.
4. Optionally expand «Рейтинги массива → Barton Q / RMR» to enter the assessment for this point/interval. Missing coefficients remain missing; numerical RMR89 is unavailable.
5. Tap «Сохранить наблюдение» to save the point and its originals together. Success keeps context and nominal horizon Z; failure keeps the draft. Tabs, DXF navigation, cancelled sheets and temporary backgrounding preserve added readings. Unsaved drafts do not survive process termination.
6. Open the project journal or a saved plan marker to inspect originals, raw/manual provenance, interpreted sets, evidence links and tectonic structures. Use «Редактировать наблюдение» for a correction, enter its reason and save a new version. «История изменений» retains original and prior values. No automatic J1–J5 interpretation is performed.

## Independent manual workflow

1. Open «Картирование → Сервисы → Измерение» and select «Геологический компас».
2. Enter dip and direction, select the recorded north type and optionally add notes. For 0° leave direction blank; for 90° confirm a conventional side if entering one.
3. Check the validation message and normalized preview, then tap «Сохранить». The same unchanged draft cannot be saved twice; «Новое измерение» starts another capture.
4. Open «Картирование → Сервисы → Неназначенные измерения» to inspect originals. «Сервисы → Настройки → Экспортировать CSV» exports the standalone measurements (mapping export is deferred).

Switching to manual stops acquisition; returning to automatic retains an existing HOLD snapshot. The automatic workflow remains HOLD → optional notes → SAVE → «Продолжить». Simulator presets and DEMO labels apply to automatic observations only.

## Data safety and export

Keep bundle identifier **`com.tinuvael.FieldForge`** and upgrade in place. Do not uninstall/reset the deployed app or change its identifier to test this release. App removal deletes sandbox data.

The active journal stays at Application Support/FieldForge/`measurements-v1.json`. Phase 2 introduces schema **2** while retaining this path. Migration preserves UUIDs, timestamps, orientations, raw diagnostics and notes. It validates all records and a v2 round trip, creates/verifies `measurements-v1.json.phase1-backup`, then replaces the active file atomically. Load, unknown-version, invalid-record or backup failures block writes and preserve the source. A conflicting backup requires explicit recovery; no automatic reset/rollback is performed. See [migration and recovery](docs/persistence-migration.md). Phase 1 cannot read v2; downgrade requires a reviewed recovery plan.

CSV uses UTF-8 BOM, comma separators, CRLF records, UTC ISO 8601 timestamps, round-trip numeric precision and empty cells for missing data. The first 24 Phase 1 column names/order are retained; four provenance/original-input columns are appended. Manual diagnostic cells are blank. Spreadsheet-formula-like text is protected. Consumers must accept additional columns/new enums and full-precision numeric formatting. Use Excel's UTF-8/comma/decimal-dot import when regional detection differs. Excel numeric precision may still reduce values; CSV is not a complete JSON/attachment backup.

The project graph uses `mapping-v1.json` (schema 7, lossless schema 1–6 upgrade with immutable `.pN-backup`, including `.p6-backup`), isolated from the protected standalone measurement journal. It is atomically rewritten as one validated aggregate; `mapping-v1.json.previous` retains the prior snapshot. No legacy assignment/migration is guessed. Managed DXF files/intents live beside it under `plans/`; photos use `photos/originals`, `photos/operations`, `photos/staging` and regenerable `photos/thumbnails`. A complete offline backup requires a consistent graph, legacy journal/backups, original photos and DXF, pending operations/staging and a verified inventory/manifest with missing-file reports. A JSON-only copy is not a complete backup. No ZIP/XLSX package or automated restore is provided yet; see [backup and recovery](docs/p4-1-photos.md). SQLite remains a future storage step for large workloads; see the [P2 storage/recovery contract](docs/p2-dxf.md).

## Branding

The current icon uses the owner-supplied faceted compass artwork. Its original master is preserved under `branding/`; regenerate the complete, proportional 1024px AppIcon with `python3 scripts/generate_app_icon.py` on macOS. See [artwork and generation details](branding/README.md).

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

Set `DEVELOPER_DIR` to a supported Xcode installation when necessary. Project generation uses Python 3 only and is deterministic. Machine-local signing overrides belong in ignored `Config/LocalSigning.xcconfig` (`DEVELOPMENT_TEAM = your Team`), optionally included by `Config/Signing.xcconfig`; they survive regeneration. Identifier and deployment settings remain unchanged. Core tests run via Swift Package Manager on macOS; managed-plan/photo integrity uses system CryptoKit and photo decoding uses ImageIO, while UI and Core Motion use Apple SDKs. Linux plan-store builds are not qualified. Debug UI tests use separate journals and UUID-scoped mapping/plan/photo stores, never physical-device journals.

```text
FieldForge/App/                  composition, lifecycle, automatic session and manual draft
FieldForge/Core/Geometry/        sensor-independent orientation, coordinates and conventions
FieldForge/Core/Sensors/         diagnostic values, Core Motion and mock adapters
FieldForge/Data/Models/          project graph, mapping draft, observation provenance, validation and HOLD
FieldForge/Data/Storage/         versioned JSON, migration, backup and integrity protection
FieldForge/Features/             Russian SwiftUI mapping/context, measurement, journals and settings
FieldForge/Services/Export/      CSV and temporary export file
FieldForge/Services/Plans/       bounded DXF adapter, viewport and managed original-file integrity
FieldForge/Services/Photos/      received originals, integrity, staging/intents and thumbnails
Tests/                          mapping/reset/context/integrity, geometry, observations, migration and CSV XCTest
UITests/                        mapping acceptance and automatic/manual save/relaunch/export workflows
scripts/generate_project.py     deterministic checked-in Xcode project
```

P4.1 verification: see [photo storage, migration, recovery and Simulator checks](docs/p4-1-verification.md). Real camera verification is a separate owner manual check.

P3.3 verification: see [saved observation revisions, compatibility and test results](docs/p3-3-verification.md).

P3.2b verification: see [Q/RMR89 methodology and automated checks](docs/p3-2b-verification.md).

P3.2a verification: see [joint sets, tectonics, compatibility and test results](docs/p3-2a-verification.md). Current P2 hotfix verification: see [Issue #14 original-DXF checks and journal search/focus results](docs/p2-hotfix-verification.md). Journal UI tests scope uniquely identified native search fields to their navigation bars and verify matching/empty results and reset. The [original P2 verification](docs/p2-verification.md) is historical. Earlier Phase 1/2 verification reports are historical. Physical measurement accuracy and device upgrade behavior still require owner validation.

## Architecture and next steps

See the authoritative [product vision](docs/product-vision.md), [development rules](AGENTS.md), [architecture and persistence decision](docs/architecture.md), [future shared domain schema](docs/data-model.md), [coordinates](docs/coordinate-systems.md), [export and prepared-plan boundaries](docs/import-export.md), and [roadmap](docs/roadmap.md).

P2 supplies individual mapping points, numeric nominal horizons and source-plan DXF positioning with a project-aware journal. P3.1/P3.2a supply original measurement capture, evidence-linked interpreted sets, optional intervals and tectonic observations; standalone interval entities, draft/point-free photos, surveyed/raster georeferencing and wedge analysis follow separately, with native iPad adaptation planned from the shared codebase. P3.3 adds immutable correction snapshots for saved points and their optional intervals. P4.1 adds photographs on saved points with frozen references to those snapshots. P3.2b adds verified NGI 2025 Q assessment; numerical RMR89, XLSX, spatial transforms and wedge calculations remain future work; mechanical wedge implementation depends on the owner's verified methodology. A whole-mine 3D viewer is not a primary product goal.
