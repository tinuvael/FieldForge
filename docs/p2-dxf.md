# P2 mapping, nominal horizon elevations and offline DXF

Current behavior: [DXF elevation snapping](gsi-chart-dxf-elevation.md) supersedes the
historical no-DXF-Z/horizontal-LINE restrictions below. Explicit WCS LINE,
3D POLYLINE and constant-elevation LWPOLYLINE segments can propose Z in metres,
with bounded XY distance, ambiguity review and manual override preservation.


**Pre-MVP owner storage decision:** mapping uses only current experimental schema **8**. No automatic mapping migrations, new `.pN-backup`, resets or deletions; old/corrupt files fail closed and all existing files are preserved. Earlier mapping-schema descriptions below are historical, not supported compatibility. Atomic current saves/`.previous`, integrity, external-change guards and immutable evidence/history remain. The independent original-measurement journal keeps its deployed compatibility. See [current storage/recovery](p4-1-photos.md) and [AGENTS.md](../AGENTS.md).

**P3.1 update:** [Integrated measurements](p3-measurements.md) supersedes historical standalone-only measurement navigation, empty measurement links and schema-1/2-only statements. Mapping now saves point-owned originals atomically in schema 3; the existing DXF contract is unchanged.

P2 implements Issue #7 on the shared mapping graph. It supersedes the P1 descriptions of coordinate entry, horizon creation, plan availability and mapping schema. No geological orientation algorithm, manual/Core Motion capture, rating or wedge calculation changes.

## Capture and elevation

The fixed Project → Horizon → Excavation panel remains. The point form contains Picket / Date, X / Y / Z metres, **Выбрать на плане**, measurement navigation, notes and Save. Chainage origin/direction, CRS, axes and coordinate provenance are no longer repeated in everyday capture or required to save. New manual coordinates use explicit `unknown` CRS/axes and `manual; accuracy unknown` provenance; omitted chainage origin/direction is `unknown`. Historical strings remain intact in original record details.

New horizons require signed numeric metre elevation (integers or decimals with comma/dot). `elevationMeters` is authoritative; labels such as `+393 м`, `+615 м`, `-120 м` are presentation. Existing horizon names and UUIDs are retained. An existing name containing a number is never parsed; unknown numeric elevation stays unknown until explicitly set in horizon management. Optional vertical datum stays in advanced horizon properties.

Selecting/reopening a known horizon suggests its nominal elevation for the next point. Suggested Z alone is clean state. Editing or deliberately clearing Z creates `manualOverride` state; XY selection, navigation and horizon-metadata updates preserve it. Clean context switching refreshes the suggestion; dirty context switching keeps the existing discard/cancel guard. Save commits before resetting. Success keeps all three context UUIDs, clears per-point values/date override and reapplies the current horizon suggestion. Failure preserves the entire draft and context. Drafts survive navigation/backgrounding in memory, not process termination.

`MappingCoordinates.zOrigin` distinguishes `horizonDefault` / `manualOverride`; nil preserves unspecified legacy provenance. A horizon default freezes horizon UUID, numeric elevation and vertical datum on the observation. Later horizon changes never update old Z. A deliberately cleared manual Z is represented even when all coordinate components are nil. Horizon Z is a **nominal designation, not surveyed point elevation**. Z is always metres, independent of the drawing's XY units. No Z comes from DXF, EXIF, GPS or device sensors.

## Offline plans and import

Each immutable `MappingPlanReference` belongs to a horizon UUID and thereby one project. Any number of plans/revisions can share a horizon; original filenames are display metadata, not identities. Import from Files uses a security-scoped URL and coordinated read; parsing is prepared off the main actor. Maximum source size is 10 MB, 300,000 group-code pairs and 200,000 display vertices. Larger/unsupported files require CAD preprocessing.

Plan setup asks once for version and XY units: unknown (default), metres, or millimetres. Original `$INSUNITS` is shown as CAD insertion-unit metadata, **not treated as verified drawing scale**. The user explicitly selects units, with no automatic numerical conversion. Unknown XY remains `drawing` units, not metres. Optional CRS and axis description stay in plan properties and default to `unknown`. Z is always a separate metre value. Feet/other source units may be viewed as unknown drawing units; convert and verify externally before assigning a metric interpretation.

Each import keeps original bytes at `plans/originals/<attachmentUUID>.dxf`, with SHA-256, byte count, filename, import time, user unit declaration, CRS/axes and source INSUNITS in the mapping graph. SHA/size are checked before each opening. Missing/corrupt files display an error and retain their records. Editing a filename/version/frame in place is unavailable: import a new immutable revision. Plans and observations are append-only in the file repository.

`plans/operations/<planUUID>.json` is written before original promotion; journal registration follows validated file storage. If registration fails, the original/operation survive. The plan list offers recovery for pending operations associated with the current horizon. Retry uses the same UUID, verifies original hash and commits idempotently. A leftover operation after a successful commit is reconciled against the graph. A manifest without original bytes, damaged manifest or file requires explicit recovery; no orphan or evidence is automatically deleted. File storage and JSON are not one filesystem transaction.

## Supported drawing subset and references

Adapter contract: **Autodesk AutoCAD 2018 ASCII DXF Reference**, entity group codes, default WCS/OCS only. Original byte encoding is preserved; parsing accepts UTF-8 (including BOM), CR/LF line endings, 999 comments or legacy text explicitly declaring ANSI_1251. Other non-UTF-8 code pages are rejected. Binary DXF and DWG are rejected. Engineering point values remain Double precision.

| Entity | Supported display | Explicit limitation |
| --- | --- | --- |
| LINE | WCS endpoints 10/20, 11/21 | Horizontal lines only; differing endpoint Z is skipped |
| LWPOLYLINE | 10/20 vertices, validated 90 count, open/closed 70 flag | Straight segments; nonzero 42 bulge is skipped for the whole entity; width is centerline only |
| POLYLINE / VERTEX / SEQEND | Straight 2D and WCS 3D (flag 8, vertex flag 32) XY projections, open/closed; plinegen 128 accepted | Mesh, polyface, fit flags, nonzero bulge and non-default extrusion skipped with counts; missing SEQEND is an error |
| POINT | WCS XY dot, original XYZ retained | Fixed 4 pt symbol; PDMODE/PDSIZE/thickness not reproduced |
| TEXT / MTEXT | Plain Unicode annotations at insertion XY; original insertion XYZ retained | See annotation subset below; visual labels are not measurements |
| ARC | Centre/radius, 50/51 degrees counterclockwise, wrapping through 0° | Default extrusion only; zero sweep rejected |
| CIRCLE | Centre/radius | Default extrusion only |
| BLOCK / INSERT | No expansion | INSERT skipped with count; no insertion/rotation/scale/base-point transforms are inferred |
| HATCH, SPLINE, ELLIPSE, DIMENSION, external references, other objects | Unsupported | Skipped by entity name with visible counts; no complete CAD representation claim |

Non-default extrusion/OCS, paper-space and entity-invisible objects are skipped with warnings. Horizontal drawing elevation is not used as observation Z. Off/frozen layer-table visibility is respected. Styles, lineweights, CAD annotation, clipping and layer selection are not reproduced. The viewer always exposes the simplified-display warning and complete warning list, including skipped entity counts. A drawing with no supported geometry or labels is rejected; POINT-only and label-only files are usable. Supported entities with malformed/duplicate mandatory numeric groups fail the import instead of becoming fabricated geometry. Unsupported objects may be present in an otherwise usable partial drawing; always review the warning list and source in CAD before field use.

Primary reference pages:

- [Autodesk 2018 LWPOLYLINE group codes](https://help.autodesk.com/cloudhelp/2018/ENU/AutoCAD-DXF/files/GUID-748FC305-F3F2-4F74-825A-61F04D757A50.htm).
- [Autodesk AutoCAD 2014 full DXF Reference](https://images.autodesk.com/adsk/files/autocad_2014_pdf_dxf_reference_enu.pdf), graphical entity chapters LINE, POLYLINE, VERTEX, ARC, CIRCLE and INSERT (same used group-code conventions).
- [Autodesk OCS conventions](https://help.autodesk.com/cloudhelp/2024/ENU/AutoCAD-DXF/files/GUID-D99F1509-E4E4-47A3-8691-92EA07DC88F5.htm) and [INSUNITS definitions](https://help.autodesk.com/cloudhelp/2025/ENU/AutoCAD-Core/files/GUID-A58A87BB-482B-4042-A00A-EEF55A2B4FD8.htm).

Arcs/circles are display chords at ≤1° increments, using the published CAD centre/radius/CCW conventions. This is a display approximation, not an engineering curve-intersection or surveying calculation. Picking is freehand drawing-space XY, without snapping. No geological/kinematic/mechanical engineering method is introduced.

## 3D projection and annotation subset (Issue #14)

3D POLYLINE source vertices retain WCS XYZ, layer, original count/order and closure
separately from display paths. The display adds only the closing edge; no source
vertex is duplicated. XY is copied without coordinate conversion. Non-default
extrusion remains conservatively unsupported and warned. Hidden/frozen layers,
entity invisibility and paper-space apply before display, including vertex checks.
A 3D plan is not a planar geological observation. Observation Z still comes only
from the selected numeric horizon or manual input; tapping a ramp never samples
its vertex Z. Managed originals and SHA-256 remain unchanged.

Annotations support literal UTF-8/declared Windows-1251, `\U+XXXX` Unicode scalars,
common `%%d/%%p/%%c` symbols, and MTEXT paragraph/nonbreaking-space/literal escapes.
TEXT supports default left/baseline placement and degree rotation; MTEXT supports
top-left placement, chunked text, radian rotation or planar X direction (last
specified orientation wins). Other justification, mirroring, oblique/width changes,
columns, rich formatting and fields are skipped with feature counts. A visible
warning qualifies the approximate native font/baseline, ignored CAD wrapping,
spacing/background, and 6–96 pt screen font clamp. Fit uses label insertion anchors,
not exact glyph extents. No font/style or full CAD layout fidelity is claimed.

References: Autodesk [2018 POLYLINE](https://help.autodesk.com/cloudhelp/2018/ENU/AutoCAD-DXF/files/GUID-ABF6B778-BE20-4B49-9B58-A94E64CEFFF3.htm)
and the **2014 DXF Reference** entity chapters POINT, TEXT, MTEXT and VERTEX linked
above. These published conventions define the bounded display adapter; no new
engineering calculation or persistence schema is introduced.

The project journal now uses searchable horizon then excavation lists with All
choices, picket/number search, optional inclusive calendar-day dates in the current
viewing time zone, explicit result counts, reset and secondary date/picket sorting.
Changing journal filters never changes capture context or records. Coordinates
read «Координаты, м» only for declared metre XY; otherwise drawing XY and Z metres
are distinguished. Horizon creation has a single numeric elevation field; optional
vertical datum metadata is on a separate screen while editing an existing horizon.
Legacy horizon names are never parsed into elevation or used to rewrite old Z.

## Viewport and saved observations

`PlanViewport` is a pure Foundation Double-precision display transform. Drawing X increases right; drawing Y increases up. View coordinates are logical SwiftUI points with Y down. Fit uses `min((width−48)/max(1, ΔX), (height−48)/max(1, ΔY))`, with positive minimum scale. Screen origin is the viewport centre plus pan; drawing origin is bounding-box centre. X uses positive scale, Y negative scale. The inverse removes pan/centre, divides by that same scale and reverses Y. Device pixel density is never multiplied in. Portrait/landscape resizing recomputes the aspect-preserving fit; the viewer offers pan, pinch zoom and fit/+/- controls, without a drawing rotation tool or georeferencing transform.

Tap empty space to propose an orange new point. **Подтвердить X/Y** applies only XY and frozen plan/version/CRS/units/hash provenance to the existing draft, then returns to Mapping. It leaves picket/date/notes/Z untouched. Subsequent manual XY editing keeps the selected drawing units/frame and records `manualInPlan`; values are never silently relabeled metres. A normal fresh manual point uses metres. Partial manual coordinates remain allowed; only complete XY can be overlaid.

Blue saved markers/picket labels query original mapping records by project + horizon + exact source plan UUID. Optional excavation filtering and a full point list are available. A marker tap opens a list of **all** records within a 24 logical-point hit radius; overlapping points stay separately selectable by UUID/date. The list opens the original read-only journal detail. Existing-point navigation never applies coordinates or changes the draft.

Manual P1 points and points from another plan/revision are hidden even if their numbers or CRS strings match. No compatibility transform is inferred. Original observations appear when linked to their actual plan; there is no cross-plan registration UI, survey georeferencing, GPS or automatic positioning. The Plan tab reuses the same list/viewer in read-only positioning mode; XY selection begins explicitly from Mapping.

## Migration and recovery

The deployed path remains **Application Support/FieldForge/mapping-v1.json**; its envelope is now schema **2**. Schema 1 decodes all old fields without deriving Z/provenance or assigning plans. Validate, change envelope version only, encode and compare complete decoded equality, preserve exact original bytes as **mapping-v1.json.p1-backup**, recheck the active bytes, then atomically promote. An identical backup allows retry; a conflicting/unreadable/partial backup, invalid graph or unknown schema blocks writes and preserves the source. Schema 2 reopens without rewrite. Normal commits retain `.previous` and the original append-only evidence check. The immutable P1 backup is never overwritten by later commits.

Preserve the whole Application Support/FieldForge directory for recovery: graph, `.previous`, `.p1-backup`, `plans/originals`, `plans/operations`, and existing measurement journals/backups. A JSON-only copy omits plan originals and is **not** a complete offline backup. Recovery should inspect copies, verify SHA-256/record graph and explicitly activate a staging repair. An export/restore UI and automatic recovery from missing originals are not included in P2. Foundation atomic writes do not claim power-loss durability or support concurrent external writers. Physical disk-full/power-loss testing remains outstanding.

`measurements-v1.json`, its Phase 1 backup, original manual/sensor records, `com.tinuvael.FieldForge`, branding and ignored Personal Team configuration remain unchanged. P2 does not install/remove/reset the physical iPhone app.

## Verification

See [Issue #14 verification](p2-hotfix-verification.md) for original-file regression results and [historical P2 verification](p2-verification.md). `DXFTests` uses hand-authored synthetic group-code fixtures and literal independent expected vertices/cardinal arc points. Viewport tests assert manually calculated screen/control coordinates after pan/zoom/aspect changes, including large coordinate rebasing. These verify the adapter and display algebra, not surveyed field accuracy or CAD completeness. Source-file picker/provider behavior and physical sensor accuracy require platform/field qualification.
