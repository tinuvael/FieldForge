# P5.1 mapping analysis CSV

Part of #10. Enter **Картирование → Журнал → Выгрузка**. This adds no primary module. Select one project, optionally a horizon and/or excavation, inclusive calendar dates and an explicit IANA time zone. The initial zone is the device zone, visibly editable; projects have no inferred zone. Changing zones preserves the selected calendar labels. Preview then save/share all CSV files and `manifest.json` through the native iOS activity controller, including Files. The standalone measurement CSV remains a separate workflow.

## Snapshot and date policy

The export screen receives a value snapshot of the saved mapping journal when opened. Preview freezes the selection and builds all table values off the main actor. Later journal edits/context changes cannot alter that preview or its files. Changing export controls invalidates the preview. Reopen the screen to obtain a newer journal snapshot. Counts describe data rows, excluding headers; empty tables still have headers and zero counts. Empty selections can be exported.

Use the latest effective `MappingObservation` exactly once per stable point UUID. `revision_id` is the correction UUID for version ≥2, or the point UUID for original version 1. Picket, field date, coordinates, geology and ratings come from that effective version. Filter **only points**, on effective `observedAt`. The Gregorian calendar in the selected zone produces `[startOfDay(first), startOfDay(last) + one calendar day)`. Day addition is calendar arithmetic, including 23/25-hour days and historical offset changes. Creation/correction/photo times do not control selection. Inverted date ranges and invalid zones are rejected.

Include every original measurement belonging to a selected point, all current interpreted sets and their evidence links, current structures and stored assessment snapshots, and all photos linked to the stable point. These related records can predate or postdate the selected period. Include required parents, excavation/horizon membership, plans referenced by current or historical photo contexts, and historical point context rows referenced by selected photos. No completeness filter requires measurements, ratings, coordinates, complete faults or image bytes. No original-image storage is opened by export.

## Contract `FieldForge-Mapping-CSV/1`

Export format versioning is independent of the unchanged mapping database format. The service accepts only `MappingJournal.currentSchemaVersion`; it implements no mapping upgrade, reset, repair or persistence write. The independent original-measurement journal is unchanged.

Each table is a file named `<table>.csv`. Columns below are in order. Every column ending in `_utc` also has a companion column appended after the listed columns, in the same relative order, named by replacing `_utc` with `_reference_seconds`. ISO timestamps show UTC to milliseconds; companion numbers retain the exact stored `Date.timeIntervalSinceReferenceDate` (seconds since **2001-01-01T00:00:00Z**) without presentation rounding. For example `observed_at_utc` has `observed_at_reference_seconds`. Recorded point zone and offset remain independent; no north/time-zone/CRS conversion overwrites source data.

| File | Columns |
| --- | --- |
| `projects` | `project_id, name` |
| `horizons` | `horizon_id, project_id, name, elevation_m, elevation_datum` |
| `excavations` | `excavation_id, project_id, name` |
| `excavation_horizons` | `excavation_id, horizon_id` |
| `plans` | `plan_id, horizon_id, attachment_id, version, file_metadata_json` |
| `points` | `point_id, revision_id, version, project_id, horizon_id, excavation_id, picket, chainage_m, chainage_origin_direction, observed_at_utc, observed_zone, observed_offset_seconds, created_at_utc, corrected_at_utc, interval_start_text, interval_start_m, interval_end_text, interval_end_m, position, x, y, z_m, xy_units, crs, axes, coordinate_source, coordinate_provenance, z_origin, z_horizon_id, z_horizon_elevation_m, z_datum, plan_id, notes` |
| `photo_point_contexts` | Same columns as `points`, one row per distinct referenced historical `revision_id` |
| `measurements` | `measurement_id, point_id, timestamp_utc, dip_direction_deg, dip_angle_deg, north, direction_meaning, source, quality, status, plane, algorithm_version, original_direction_text, original_dip_text, notes, sensor_sample_json, orientation_json` |
| `joint_sets` | `joint_set_id, point_id, revision, identifier, interpreted_at_utc, author, method, dip_direction_deg, dip_angle_deg, north, direction_meaning, original_direction_text, original_dip_text, spacing_m, persistence_m, aperture_mm, roughness, infill, notes` |
| `interpretation_evidence` | `joint_set_id, joint_set_revision, point_id, measurement_id, role` |
| `tectonic_structures` | `structure_id, point_id, type, dip_direction_deg, dip_angle_deg, north, original_direction_text, original_dip_text, conventional_dip_side, thickness_m, picket_text, chainage_m, position, description` |
| `assessments` | `point_id, kind, method, revision, assessed_at_utc, stored_q, stored_q_class, rqd_text, jn_text, jr_text, ja_text, jw_text, srf_text, input_json, stored_evaluation_json, missing_json, rmr_strength_test, rmr_strength_mpa_text, rmr_strength_evidence, rmr_rqd_evidence, rmr_spacing_m_text, rmr_persistence_m_text, rmr_aperture_mm_text, rmr_roughness, rmr_infill, rmr_weathering, rmr_groundwater, rmr_inflow_l_min_per_10m_text, rmr_water_pressure_ratio_text, rmr_application, rmr_orientation_description, rmr_source, rmr_assessor, rmr_missing_reason, rmr_status` |
| `photos` | `photo_id, point_id, project_id, horizon_id, excavation_id, context_revision_id, context_point_version, capture_location_basis, name, number, description, category, metadata_revision_id, metadata_version, metadata_corrected_at_utc, source, captured_at_utc, capture_time_text, capture_time_provenance, imported_at_utc, attachment_id, original_integrity` |
| `photo_attachments` | `attachment_id, original_filename, sha256_expected, byte_count_expected, format, mime_type, pixel_width, pixel_height, orientation, representation, original_integrity` |

Keys and joins:

- `points.point_id` is unique. Child `point_id` references it. Point `revision_id/version` scopes current interpretations/assessments; the export omits correction audit history.
- `joint_sets.joint_set_id` and `measurements.measurement_id` are unique within the export. Evidence rows reference both, plus the interpreted set revision. Role is `interpretationEvidence`. Interpreted representatives are never manufactured from automatic clustering.
- `assessments` has composite key `(point_id, kind)` (`Q` or `RMR89-input-only`). Input/missing/evaluation JSON is the stored snapshot, never a new evaluation. RMR numerical score/class fields remain empty. Q method/version, original coefficient text, category choices, adjustments, rationale, missing reasons and used/result values are retained. No new rating or rock-mechanics method is implemented.
- `photos.context_revision_id` references `photo_point_contexts.revision_id`; those rows are historical **linkage context**, not additional selected/current observations. Their coordinates, interval, zone/offset, plan identity/version and chainage provenance describe that historical point. Current location comes only from `points`. If `capture_location_basis=unknownBeforeFirstSave`, **capture location is unknown**, regardless of any coordinates in either linked point row. Do not interpret the first-save linkage context as a capture-location measurement. For `pointRevision`, the frozen historical context is the declared photo point context, never GPS positioning.
- Effective photo names/numbers/descriptions/categories and metadata revision identity are selected from the same snapshot. Original photo capture timestamp may be empty even when EXIF wall-time text exists; import time is separate. Metadata version 1 uses photo UUID as its revision identity. Attachments join by `attachment_id`, never filename.
- Attachment SHA-256/size are **expected stored metadata**. `original_integrity=notChecked; originalsNotIncluded` means availability and hash verification were not attempted. Missing/unreadable originals cannot remove these rows. No private EXIF GPS is read. User filenames/descriptions can still contain private information.
- Relevant parent IDs resolve through project/horizon/excavation tables and `excavation_horizons`; a selected excavation's other horizon memberships may require additional same-project horizon rows. Parent metadata is current at the journal snapshot, not a versioned history of renamed parents.

### Detailed JSON cells

These cells preserve detail without an unbounded set of diagnostic columns. They are sorted-key JSON using the existing stored model field names. Optional stored fields may be absent; do not replace absence with zero. JSON dates are numeric reference seconds using the epoch above. JSON numbers retain stored Double precision.

- `plans.file_metadata_json`: managed plan metadata including source filename/hash/size, import time, units/unit declaration, CRS and axes. No DXF bytes are included; an attachment UUID here is metadata identity, not a photo-table foreign key.
- `measurements.sensor_sample_json`: complete stored sensor frame/source, timestamp, matrix, quaternion, gravity, magnetic field/accuracy and motion diagnostics. Empty for manual entries. Units/axes follow [measurement conventions](p3-measurements.md) and the original sensor model (NWU orientation, device-frame diagnostics, g, µT, rad/s). `orientation_json` retains stored orientation/status/normal.
- `assessments.input_json`: all stored `BartonQInput` or `RMR89Input` fields. `stored_evaluation_json` is the stored Q result/missing list; empty for RMR. `missing_json` is the stored list, including an empty array when complete. No constructor/evaluation is called during export.

XY use declared `xy_units` (`m`, `mm`, `drawing`); Z/elevations, intervals, chainage, spacing/persistence/thickness use meters; aperture uses millimeters; dip/direction use degrees. North, horizontal/vertical ambiguity, manual original strings, interpretation method and sensor algorithm versions remain explicit. Partial fault angle components remain independently empty. Missing plan/alignment information remains missing; no survey alignment or transformations are inferred.

## CSV and spreadsheet handling

UTF-8 BOM (`EF BB BF`), comma separator, CRLF records including final terminator, every cell quoted, embedded quotes doubled; embedded newlines are retained. Empty/missing values are `""`, never zero. Numeric engineering columns use locale-independent shortest round-trip `Double` strings (including signed/exponent notation) and receive no text protection. UUIDs and enums are text.

For text, prepend one apostrophe when the first character after whitespace/control trimming is `=`, `+`, `-`, `@` or apostrophe, or the original first character is tab/CR/LF. This includes original numeric **text** fields when they begin with a sign. Consumers reading such protected text can remove one prefix apostrophe according to this rule; apostrophe-leading original text is doubled. CSV is an analysis interchange, not a canonical exact-string backup. Quoting alone is not formula protection.

Excel typically retains only 15 significant numeric digits and can infer data types even for quoted fields. Import original decimal-text columns as **Text** when exact spelling is required, particularly decimal commas and long strings; original text is retained wherever the model has it. Preserve original CSV bytes for precision-sensitive analysis, and use the exact reference-seconds/JSON fields rather than millisecond display timestamps. Changing spreadsheet formatting cannot recover digits already lost by its parser.

`manifest.json` contains format/export identity, snapshot timestamp and exact reference seconds, project/optional scopes, inclusive date labels, Gregorian calendar/time zone, exclusive UTC interval, effective-version policy, every filename/header/count, encoding policy and limitations. It is descriptive metadata, not a database backup.

## Ownership, cancellation and limitations

The writer creates a fresh UUID directory in temporary storage, writes only its own CSV/manifest files and returns all URLs together. Failure/cancellation removes only that directory. The native share presentation retains file ownership until dismissal; completing/cancelling sharing removes the directory. A second share recreates files from the same preview. Process termination may leave export temporary data for OS reclamation; no broad cache sweep touches other exports or source files. Export cannot change the journal, originals, pending photo operations or unsaved capture draft. There is no XLSX, original-image archive, backup/restore, DXF modification, LiDAR or wedge work in this stage. #10 remains open for later stages.

See [verification](p5-1-verification.md) for actual checks and remaining manual coverage.
