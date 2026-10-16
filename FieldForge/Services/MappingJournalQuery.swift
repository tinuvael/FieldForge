import Foundation

/// Read-only query; project is mandatory, other scopes are optional. Date endpoints
/// represent inclusive calendar days in the journal viewer's current calendar/time zone.
struct MappingJournalQuery {
    var horizonID: UUID?
    var excavationID: UUID?
    var picket = ""
    var startDate: Date?
    var endDate: Date?
    var byPicket = false

    func apply(_ records: [MappingObservation], projectID: UUID?, calendar: Calendar = .current) -> [MappingObservation] {
        guard let projectID else { return [] }
        let start = startDate.map { calendar.startOfDay(for: $0) }
        let end = endDate.flatMap { calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: $0)) }
        let search = picket.trimmingCharacters(in: .whitespacesAndNewlines)
        return records.filter {
            $0.projectID == projectID && (horizonID == nil || $0.horizonID == horizonID)
                && (excavationID == nil || $0.excavationID == excavationID)
                && (search.isEmpty || $0.picket.localizedCaseInsensitiveContains(search)
                    || CSVExporter.number($0.chainageMeters).contains(search))
                && (start == nil || $0.observedAt >= start!) && (end == nil || $0.observedAt < end!)
        }.sorted {
            if byPicket, $0.chainageMeters != $1.chainageMeters { return $0.chainageMeters < $1.chainageMeters }
            if $0.observedAt != $1.observedAt { return $0.observedAt > $1.observedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}

enum MappingCoordinateText {
    static func xyUnit(_ units: String) -> String {
        switch units { case "m": return "м"; case "mm": return "мм"; default: return "ед. чертежа" }
    }
    static func header(xyUnits: String) -> String {
        xyUnits == "m" ? "Координаты, м" : "Координаты · X/Y — \(xyUnit(xyUnits)) · Z — м"
    }
}
