import Foundation

enum CSVExporter {
    static let columns = ["measurement_id", "timestamp_utc", "dip_direction_deg", "dip_angle_deg",
                          "geographic_reference", "reference_frame", "validity_status", "quality",
                          "sensor_source", "magnetic_accuracy", "magnetic_field_uT", "user_acceleration_g",
                          "rotation_rate_rad_s", "normal_north", "normal_west", "normal_up",
                          "gravity_x", "gravity_y", "gravity_z", "rotation_matrix_row_major",
                          "quaternion_xyzw", "measurement_plane", "algorithm_version", "notes"]
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
    static func data(_ measurements: [Measurement]) -> Data {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let rows = measurements.map { m -> String in
            let s = m.sample, n = m.orientation.normal
            let fields = [m.id.uuidString, formatter.string(from: m.timestamp),
                          number(m.orientation.dipDirection), number(m.orientation.dipAngle),
                          m.reference.rawValue, s.referenceFrame.rawValue, m.orientation.status.rawValue,
                          m.quality.rawValue, s.source.rawValue, s.magneticAccuracy.rawValue,
                          number(s.magneticField.length), number(s.userAcceleration.length), number(s.rotationRate.length),
                          number(n?.x), number(n?.y), number(n?.z),
                          number(s.gravity.x), number(s.gravity.y), number(s.gravity.z),
                          s.rotation.elements.map { number($0) }.joined(separator: " "),
                          [s.quaternion.x, s.quaternion.y, s.quaternion.z, s.quaternion.w]
                            .map { number($0) }.joined(separator: " "),
                          m.plane, m.algorithmVersion, m.notes]
            // Numeric fields never receive text sanitization (signed diagnostics remain numeric).
            return fields.enumerated().map { index, field in
                index == columns.count - 1 ? escape(field)
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
