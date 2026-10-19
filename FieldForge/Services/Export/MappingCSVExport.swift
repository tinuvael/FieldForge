import Foundation

/// Calendar dates are interpreted in this explicit zone, independently of device/project context.
struct MappingExportSelection: Equatable {
    let projectID: UUID
    var horizonID: UUID?
    var excavationID: UUID?
    let firstDay: Date
    let lastDay: Date
    let timeZoneID: String

    func bounds() throws -> (calendar: Calendar, start: Date, end: Date) {
        guard let zone = TimeZone(identifier: timeZoneID), firstDay.timeIntervalSince1970.isFinite,
              lastDay.timeIntervalSince1970.isFinite else { throw MappingError.invalid("Укажите корректные даты и часовой пояс.") }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let start = calendar.startOfDay(for: firstDay), last = calendar.startOfDay(for: lastDay)
        guard start <= last, let end = calendar.date(byAdding: .day, value: 1, to: last) else {
            throw MappingError.invalid("Дата окончания должна быть не раньше даты начала.")
        }
        return (calendar, start, end)
    }
}

/// Versioned, intentionally small mapping analysis contract. Values own their data;
/// neither generation nor sharing can read a subsequently changed workflow/draft.
struct MappingCSVExport {
    static let version = "FieldForge-Mapping-CSV/1"
    struct Table {
        let name: String
        let columns: [String]
        var rows: [[Cell]] = []
        var data: Data {
            let lines = [columns.map { Cell.text($0).csv }.joined(separator: ",")] + rows.map { $0.map(\.csv).joined(separator: ",") }
            return Data(("\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n").utf8)
        }
    }
    enum Cell {
        case text(String), number(Double?), integer(Int?), timestamp(Date?), empty
        var csv: String {
            let value: String
            switch self {
            case .text(let text):
                // Guard whitespace/control-prefixed formulas and preserve literal leading apostrophes.
                let first = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters)).first
                value = first.map { "=+-@'".contains($0) } == true || text.first.map({ "\t\r\n".contains($0) }) == true ? "'" + text : text
            case .number(let n): value = CSVExporter.engineeringNumber(n)
            case .integer(let n): value = n.map(String.init) ?? ""
            case .timestamp(let date): value = date.map(MappingCSVExport.iso) ?? ""
            case .empty: value = ""
            }
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
    }
    let id: UUID
    let snapshotAt: Date
    let selection: MappingExportSelection
    let tables: [Table]
    let manifest: Data
    var pointCount: Int { tables.first { $0.name == "points" }?.rows.count ?? 0 }

    static func prepare(journal: MappingJournal, selection: MappingExportSelection, now: Date = Date(), id: UUID = UUID()) throws -> Self {
        try Task.checkCancellation()
        guard journal.schemaVersion == MappingJournal.currentSchemaVersion else { throw MappingDatabaseError.incompatibleVersion(journal.schemaVersion) }
        let bounds = try selection.bounds()
        guard journal.projects.contains(where: { $0.id == selection.projectID }),
              selection.horizonID.map({ h in journal.horizons.contains { $0.id == h && $0.projectID == selection.projectID } }) ?? true,
              selection.excavationID.map({ e in journal.excavations.contains { $0.id == e && $0.projectID == selection.projectID && (selection.horizonID.map($0.horizonIDs.contains) ?? true) } }) ?? true else { throw StorageError.invalidRecord }
        let points = journal.effectiveObservations.filter {
            $0.projectID == selection.projectID && (selection.horizonID == nil || $0.horizonID == selection.horizonID) &&
            (selection.excavationID == nil || $0.excavationID == selection.excavationID) && $0.observedAt >= bounds.start && $0.observedAt < bounds.end
        }.sorted { $0.id.uuidString < $1.id.uuidString }
        let pointIDs = Set(points.map(\.id))
        let photos = journal.photos.filter { pointIDs.contains($0.context.pointID) }.sorted { $0.id.uuidString < $1.id.uuidString }
        let historical = try photos.map { photo -> MappingObservation in
            guard let point = journal.photoPoint(photo.context) else { throw StorageError.invalidRecord }; return point
        }
        let allPoints = points + historical
        let excavationIDs = Set(allPoints.map(\.excavationID))
        let excavations = journal.excavations.filter { excavationIDs.contains($0.id) }
        let horizonIDs = Set(allPoints.map(\.horizonID)).union(excavations.flatMap(\.horizonIDs))
        let planIDs = Set(allPoints.compactMap { $0.coordinates?.planID })
        var tables: [Table] = []
        func table(_ name: String, _ columns: [String], _ rows: [[Cell]]) {
            // ISO strings are convenient for spreadsheets; reference seconds retain exact Date precision.
            let timeIndices = columns.indices.filter { columns[$0].hasSuffix("_utc") }
            let exactColumns = timeIndices.map { String(columns[$0].dropLast(4)) + "_reference_seconds" }
            let exactRows = rows.map { row in row + timeIndices.map { i in
                if case .timestamp(let date) = row[i] { return Cell.number(date?.timeIntervalSinceReferenceDate) }
                return Cell.empty
            } }
            tables.append(Table(name: name, columns: columns + exactColumns, rows: exactRows))
        }
        func t(_ value: String?) -> Cell { value.map(Cell.text) ?? .empty }
        func u(_ value: UUID?) -> Cell { t(value?.uuidString) }
        func d(_ value: Date?) -> Cell { .timestamp(value) }
        func json<T: Encodable>(_ value: T?) throws -> Cell {
            guard let value else { return .empty }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .deferredToDate
            return .text(String(decoding: try encoder.encode(value), as: UTF8.self))
        }
        table("projects", ["project_id", "name"], journal.projects.filter { $0.id == selection.projectID }.map { [u($0.id), t($0.name)] })
        table("horizons", ["horizon_id", "project_id", "name", "elevation_m", "elevation_datum"], journal.horizons.filter { horizonIDs.contains($0.id) }.map { [u($0.id), u($0.projectID), t($0.name), .number($0.elevationMeters), t($0.elevationDatum)] })
        table("excavations", ["excavation_id", "project_id", "name"], excavations.map { [u($0.id), u($0.projectID), t($0.name)] })
        table("excavation_horizons", ["excavation_id", "horizon_id"], excavations.flatMap { e in e.horizonIDs.sorted { $0.uuidString < $1.uuidString }.map { [u(e.id), u($0)] } })
        table("plans", ["plan_id", "horizon_id", "attachment_id", "version", "file_metadata_json"], try journal.plans.filter { planIDs.contains($0.id) }.map { [u($0.id), u($0.horizonID), u($0.attachmentID), t($0.version), try json($0.file)] })
        let pointColumns = ["point_id", "revision_id", "version", "project_id", "horizon_id", "excavation_id", "picket", "chainage_m", "chainage_origin_direction", "observed_at_utc", "observed_zone", "observed_offset_seconds", "created_at_utc", "corrected_at_utc", "interval_start_text", "interval_start_m", "interval_end_text", "interval_end_m", "position", "x", "y", "z_m", "xy_units", "crs", "axes", "coordinate_source", "coordinate_provenance", "z_origin", "z_horizon_id", "z_horizon_elevation_m", "z_datum", "plan_id", "notes"]
        func pointRow(_ p: MappingObservation, revisionID: UUID, version: Int) -> [Cell] {
            let c = p.coordinates, g = p.geology
            let correction = journal.revisions.first { $0.id == revisionID }
            var row: [Cell] = [u(p.id), u(revisionID), .integer(version), u(p.projectID), u(p.horizonID), u(p.excavationID), t(p.picket), .number(p.chainageMeters), t(p.chainageOriginAndDirection), d(p.observedAt), t(p.observedTimeZoneID), .integer(p.observedUTCOffsetSeconds), d(p.createdAt), d(correction?.correctedAt)]
            row += [t(g?.start?.text), .number(g?.start?.meters), t(g?.end?.text), .number(g?.end?.meters), t(g?.position?.rawValue)]
            row += [.number(c?.x), .number(c?.y), .number(c?.z), t(c?.units), t(c?.crs), t(c?.axes), t(c?.source), t(c?.provenance), t(c?.zOrigin?.rawValue), u(c?.zHorizonID), .number(c?.zHorizonElevation), t(c?.zDatum), u(c?.planID), t(p.notes)]
            return row
        }
        table("points", pointColumns, points.map { p in
            let r = journal.history(for: p.id).last
            return pointRow(p, revisionID: r?.id ?? p.id, version: r?.version ?? 1)
        })
        // Historical rows are context only, never additional current observations or capture coordinates.
        var seen = Set<UUID>()
        table("photo_point_contexts", pointColumns, zip(photos, historical).compactMap { photo, point in
            guard seen.insert(photo.context.pointRevisionID).inserted else { return nil }
            return pointRow(point, revisionID: photo.context.pointRevisionID, version: photo.context.pointVersion)
        })
        var measurementRows: [[Cell]] = [], sets: [[Cell]] = [], links: [[Cell]] = [], faults: [[Cell]] = [], ratings: [[Cell]] = []
        for p in points {
            try Task.checkCancellation()
            for measurementID in p.measurementIDs {
                guard let m = journal.measurements.first(where: { $0.id == measurementID }) else { throw StorageError.invalidRecord }
                measurementRows.append([u(m.id), u(p.id), d(m.timestamp), .number(m.orientation.dipDirection), .number(m.orientation.dipAngle), t(m.reference.rawValue), t(m.directionMeaning.rawValue), t(m.source.rawValue), t(m.quality.rawValue), t(m.orientation.status.rawValue), t(m.plane), t(m.algorithmVersion), t(m.manualInput?.dipDirectionText), t(m.manualInput?.dipAngleText), t(m.notes), try json(m.sample), try json(m.orientation)])
            }
            for s in p.geology?.jointSets ?? [] {
                let orientation = try s.representative.validated()
                sets.append([u(s.id), u(p.id), .integer(s.revision), t(s.identifier.rawValue), d(s.interpretedAt), t(s.author), t(s.method), .number(orientation.orientation.dipDirection), .number(orientation.orientation.dipAngle), t(s.representative.reference.rawValue), t(orientation.meaning.rawValue), t(s.representative.dipDirectionText), t(s.representative.dipAngleText), .number(s.spacingMeters), .number(s.persistenceMeters), .number(s.apertureMillimeters), t(s.roughness), t(s.infill), t(s.notes)])
                for m in s.measurementIDs { links.append([u(s.id), .integer(s.revision), u(p.id), u(m), t("interpretationEvidence")]) }
            }
            for f in p.geology?.tectonicStructures ?? [] {
                let o = try f.orientation.validatedTectonic()
                faults.append([u(f.id), u(p.id), t(f.type.rawValue), .number(o.dipDirection), .number(o.dipAngle), t(f.orientation.reference.rawValue), t(f.orientation.dipDirectionText), t(f.orientation.dipAngleText), t(String(f.orientation.usesConventionalDipSide)), .number(f.thicknessMeters), t(f.picket?.text), .number(f.picket?.meters), t(f.position), t(f.description)])
            }
            if let q = p.ratings?.bartonQ {
                ratings.append([u(p.id), t("Q"), t(q.method), .integer(q.revision), d(q.assessedAt), .number(q.evaluation.result?.value), t(q.evaluation.result?.rockClass?.rawValue), t(q.input.rqd), t(q.input.jn.value), t(q.input.jr.value), t(q.input.ja.value), t(q.input.jw.value), t(q.input.srf.value), try json(q.input), try json(q.evaluation), try json(q.evaluation.missing)] + Array(repeating: Cell.empty, count: 19))
            }
            if let r = p.ratings?.rmr89 {
                ratings.append([u(p.id), t("RMR89-input-only"), t(r.method), .integer(r.revision), d(r.assessedAt), .empty, .empty, t(r.input.rqd), .empty, .empty, .empty, .empty, .empty, try json(r.input), .empty, try json(r.missing),
                    t(r.input.strengthTest?.rawValue), t(r.input.strengthMPa), t(r.input.strengthEvidence), t(r.input.rqdEvidence), t(r.input.spacingMeters), t(r.input.persistenceMeters), t(r.input.apertureMillimeters), t(r.input.roughness), t(r.input.infill), t(r.input.weathering), t(r.input.groundwater), t(r.input.inflowLitersPerMinutePer10m), t(r.input.waterPressureRatio), t(r.input.application?.rawValue), t(r.input.orientationDescription), t(r.input.source), t(r.input.assessor), t(r.input.missingReason), t("inputOnly")])
            }
        }
        table("measurements", ["measurement_id", "point_id", "timestamp_utc", "dip_direction_deg", "dip_angle_deg", "north", "direction_meaning", "source", "quality", "status", "plane", "algorithm_version", "original_direction_text", "original_dip_text", "notes", "sensor_sample_json", "orientation_json"], measurementRows)
        table("joint_sets", ["joint_set_id", "point_id", "revision", "identifier", "interpreted_at_utc", "author", "method", "dip_direction_deg", "dip_angle_deg", "north", "direction_meaning", "original_direction_text", "original_dip_text", "spacing_m", "persistence_m", "aperture_mm", "roughness", "infill", "notes"], sets)
        table("interpretation_evidence", ["joint_set_id", "joint_set_revision", "point_id", "measurement_id", "role"], links)
        table("tectonic_structures", ["structure_id", "point_id", "type", "dip_direction_deg", "dip_angle_deg", "north", "original_direction_text", "original_dip_text", "conventional_dip_side", "thickness_m", "picket_text", "chainage_m", "position", "description"], faults)
        table("assessments", ["point_id", "kind", "method", "revision", "assessed_at_utc", "stored_q", "stored_q_class", "rqd_text", "jn_text", "jr_text", "ja_text", "jw_text", "srf_text", "input_json", "stored_evaluation_json", "missing_json", "rmr_strength_test", "rmr_strength_mpa_text", "rmr_strength_evidence", "rmr_rqd_evidence", "rmr_spacing_m_text", "rmr_persistence_m_text", "rmr_aperture_mm_text", "rmr_roughness", "rmr_infill", "rmr_weathering", "rmr_groundwater", "rmr_inflow_l_min_per_10m_text", "rmr_water_pressure_ratio_text", "rmr_application", "rmr_orientation_description", "rmr_source", "rmr_assessor", "rmr_missing_reason", "rmr_status"], ratings)
        table("photos", ["photo_id", "point_id", "project_id", "horizon_id", "excavation_id", "context_revision_id", "context_point_version", "capture_location_basis", "name", "number", "description", "category", "metadata_revision_id", "metadata_version", "metadata_corrected_at_utc", "source", "captured_at_utc", "capture_time_text", "capture_time_provenance", "imported_at_utc", "attachment_id", "original_integrity"], photos.map { photo in
            let m = journal.metadata(for: photo), r = journal.photoRevisions.last { $0.photoID == photo.id }, c = photo.context
            return [u(photo.id), u(c.pointID), u(c.projectID), u(c.horizonID), u(c.excavationID), u(c.pointRevisionID), .integer(c.pointVersion), t(c.locationBasis.rawValue), t(m.name), t(m.number), t(m.description), t(m.category?.rawValue), u(r?.id ?? photo.id), .integer(r?.version ?? 1), d(r?.correctedAt), t(photo.source.rawValue), d(photo.capturedAt), t(photo.captureTimeText), t(photo.captureTimeProvenance), d(photo.importedAt), u(photo.attachmentID), t("notChecked; originalsNotIncluded")]
        })
        let attachmentIDs = Set(photos.map(\.attachmentID))
        table("photo_attachments", ["attachment_id", "original_filename", "sha256_expected", "byte_count_expected", "format", "mime_type", "pixel_width", "pixel_height", "orientation", "representation", "original_integrity"], journal.photoAttachments.filter { attachmentIDs.contains($0.id) }.map { a in
            [u(a.id), t(a.originalFilename), t(a.sha256), .integer(a.byteCount), t(a.format), t(a.mimeType), .integer(a.pixelWidth), .integer(a.pixelHeight), .integer(a.orientation), t(a.representation), t("notChecked; originalsNotIncluded")]
        })
        let dateFormatter = DateFormatter(); dateFormatter.calendar = bounds.calendar; dateFormatter.timeZone = bounds.calendar.timeZone
        dateFormatter.locale = Locale(identifier: "en_US_POSIX"); dateFormatter.dateFormat = "yyyy-MM-dd"
        let manifest: [String: Any] = ["format": version, "export_id": id.uuidString, "snapshot_at_utc": iso(now), "snapshot_reference_seconds": now.timeIntervalSinceReferenceDate,
            "project_id": selection.projectID.uuidString, "horizon_id": selection.horizonID?.uuidString ?? NSNull(), "excavation_id": selection.excavationID?.uuidString ?? NSNull(),
            "first_day_inclusive": dateFormatter.string(from: selection.firstDay), "last_day_inclusive": dateFormatter.string(from: selection.lastDay), "calendar": "gregorian", "timezone": selection.timeZoneID, "start_inclusive_utc": iso(bounds.start), "end_exclusive_utc": iso(bounds.end),
            "effective_policy": "One latest effective point per stable UUID; version 1 revision_id is point_id. Photo contexts are historical reference rows, not selected observations. No correction audit history.",
            "tables": Dictionary(uniqueKeysWithValues: tables.map { ($0.name + ".csv", ["rows": $0.rows.count, "columns": $0.columns] as [String: Any]) }),
            "encoding": "UTF-8 BOM; comma; CRLF; all cells quoted; embedded quotes doubled. Formula-like text prefixed with apostrophe, including leading apostrophes/control characters. Numbers use round-trip Double strings; nulls empty. Excel may truncate numbers beyond 15 significant digits; retain original text/JSON.",
            "limitations": ["Analysis export, not a complete backup; no image originals, thumbnails, DXF bytes or full audit history.", "Original file availability/integrity not checked; missing originals do not exclude metadata.", "unknownBeforeFirstSave means capture location UNKNOWN; referenced point context is linkage context only, never capture coordinates.", "No north/CRS conversions; XY declared units, Z and chainage meters, orientation degrees. No rating recalculation; RMR input only.", "ISO UTC timestamps have millisecond display precision; companion *_reference_seconds values are exact stored Date seconds since 2001-01-01T00:00:00Z. JSON dates use the same epoch. Nested JSON cells retain detailed stored input/diagnostics; no EXIF GPS is read or exported. Private text/filenames may be present."]]
        return Self(id: id, snapshotAt: now, selection: selection, tables: tables, manifest: try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]))
    }

    static func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }
}

/// Owns only a newly created UUID directory. Sources are never opened or modified.
final class MappingExportFiles {
    let directory: URL
    let urls: [URL]
    private init(directory: URL, urls: [URL]) { self.directory = directory; self.urls = urls }
    static func write(_ export: MappingCSVExport, parent: URL = FileManager.default.temporaryDirectory,
                      format: MappingExportFormat = .csv,
                      write: (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) },
                      xlsxAppend: @escaping (Data, FileHandle) throws -> Void = { try $1.write(contentsOf: $0) }) throws -> MappingExportFiles {
        try Task.checkCancellation()
        let directory = parent.appendingPathComponent("FieldForge-Mapping-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        do {
            if format == .xlsx {
                let url = directory.appendingPathComponent("FieldForge-Mapping.xlsx")
                try MappingXLSXExport.write(export, to: url, append: xlsxAppend)
                try Task.checkCancellation()
                return MappingExportFiles(directory: directory, urls: [url])
            }
            var urls: [URL] = []
            for table in export.tables {
                try Task.checkCancellation()
                let url = directory.appendingPathComponent(table.name + ".csv")
                try write(table.data, url); urls.append(url)
            }
            let manifestURL = directory.appendingPathComponent("manifest.json")
            try write(export.manifest, manifestURL); urls.append(manifestURL)
            try Task.checkCancellation()
            return MappingExportFiles(directory: directory, urls: urls)
        } catch { try? FileManager.default.removeItem(at: directory); throw error }
    }
    func cleanup() { try? FileManager.default.removeItem(at: directory) }
    deinit { cleanup() }
}
