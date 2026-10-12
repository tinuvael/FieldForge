import Foundation

enum CSVExporter {
    static let columns = ["measurement_id", "timestamp_utc", "dip_direction_deg", "dip_angle_deg",
                          "geographic_reference", "reference_frame", "validity_status", "quality",
                          "sensor_source", "magnetic_accuracy", "magnetic_field_uT", "user_acceleration_g",
                          "rotation_rate_rad_s", "normal_north", "normal_west", "normal_up",
                          "gravity_x", "gravity_y", "gravity_z", "rotation_matrix_row_major",
                          "quaternion_xyzw", "measurement_plane", "algorithm_version", "notes",
                          "measurement_source", "dip_direction_meaning", "original_dip_direction_text",
                          "original_dip_angle_text"]
    static func number(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "" }
        return String(format: "%.8f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
    static func escape(_ value: String) -> String {
        // Prevent text supplied as notes from becoming an Excel formula.
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let safe = ["=", "+", "-", "@"].contains(String(trimmed.prefix(1))) ? "'" + value : value
        return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
    /// Shortest locale-independent representation that round trips to the same Double.
    static func engineeringNumber(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "" }
        return String(value)
    }
    static func data(_ measurements: [Measurement]) -> Data {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let rows = measurements.map { m -> String in
            let s = m.sample, n = m.orientation.normal
            let matrix = s?.rotation.elements.map { engineeringNumber($0) }.joined(separator: " ") ?? ""
            let quaternion = s.map { value in
                [value.quaternion.x, value.quaternion.y, value.quaternion.z, value.quaternion.w]
                    .map { engineeringNumber($0) }.joined(separator: " ")
            } ?? ""
            var fields: [String] = [m.id.uuidString, formatter.string(from: m.timestamp),
                          engineeringNumber(m.orientation.dipDirection), engineeringNumber(m.orientation.dipAngle),
                          m.reference.rawValue, s?.referenceFrame.rawValue ?? "", m.orientation.status.rawValue,
                          m.quality.rawValue, s?.source.rawValue ?? "", s?.magneticAccuracy.rawValue ?? ""]
            fields += [
                          engineeringNumber(s?.magneticField.length), engineeringNumber(s?.userAcceleration.length),
                          engineeringNumber(s?.rotationRate.length),
                          engineeringNumber(n?.x), engineeringNumber(n?.y), engineeringNumber(n?.z),
                          engineeringNumber(s?.gravity.x), engineeringNumber(s?.gravity.y), engineeringNumber(s?.gravity.z),
                          matrix, quaternion]
            fields += [
                          m.plane, m.algorithmVersion, m.notes, m.source.rawValue, m.directionMeaning.rawValue,
                          m.manualInput?.dipDirectionText ?? "", m.manualInput?.dipAngleText ?? ""]
            // Numeric fields never receive text sanitization (signed diagnostics remain numeric).
            return fields.enumerated().map { index, field in
                [23, 26, 27].contains(index) ? escape(field)
                    : "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            }.joined(separator: ",")
        }
        return Data(("\u{FEFF}" + ([columns.joined(separator: ",")] + rows).joined(separator: "\r\n") + "\r\n").utf8)
    }
    static func writeTemporaryFile(_ measurements: [Measurement]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("FieldForgeExports")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("FieldForge-\(UUID().uuidString).csv")
        try data(measurements).write(to: url, options: .atomic)
        return url
    }
}
