import XCTest
#if canImport(FieldForgeCore)
@testable import FieldForgeCore
#else
@testable import FieldForge
#endif

final class MappingJournalQueryTests: XCTestCase {
    func testProjectHorizonExcavationSearchInclusiveDatesAndOptionalSort() throws {
        let (_, initial) = try P2MappingTests().configured(); var w = initial
        let project = w.context.projectID!, horizon = w.context.horizonID!, excavation = w.context.excavationID!
        w.draft.picketConvention = .legacyMeters; w.draft.picket = "ПК 0+010"; let a = try w.save(now: Date(timeIntervalSince1970: 86400))
        w.draft.picketConvention = .legacyMeters; w.draft.picket = "ПК 0+005"; let b = try w.save(now: Date(timeIntervalSince1970: 172799.999))
        let otherHorizon = try w.createHorizon(elevation: "615")
        try w.requestContext(MappingContext(projectID: project, horizonID: otherHorizon))
        let otherExcavation = try w.createExcavation(name: "Other", horizonIDs: [otherHorizon])
        try w.requestContext(MappingContext(projectID: project, horizonID: otherHorizon, excavationID: otherExcavation))
        w.draft.picketConvention = .legacyMeters; w.draft.picket = "ПК 0+015"; let c = try w.save(now: Date(timeIntervalSince1970: 172800))
        let secondProject = try w.createProject(name: "Second")
        try w.requestContext(MappingContext(projectID: secondProject))
        let secondHorizon = try w.createHorizon(elevation: "200")
        try w.requestContext(MappingContext(projectID: secondProject, horizonID: secondHorizon))
        let secondExcavation = try w.createExcavation(name: "Other", horizonIDs: [secondHorizon])
        try w.requestContext(MappingContext(projectID: secondProject, horizonID: secondHorizon, excavationID: secondExcavation))
        w.draft.picketConvention = .legacyMeters; w.draft.picket = "ПК 0+005"; _ = try w.save(now: Date(timeIntervalSince1970: 90000))
        let all = w.journal.observations
        var query = MappingJournalQuery()
        XCTAssertEqual(query.apply(all, projectID: project), [c,b,a])
        XCTAssertTrue(query.apply(all, projectID: nil).isEmpty)
        query.horizonID = horizon
        XCTAssertEqual(query.apply(all, projectID: project), [b,a])
        query.excavationID = otherExcavation
        XCTAssertTrue(query.apply(all, projectID: project).isEmpty)
        query.excavationID = excavation; query.picket = "005"
        XCTAssertEqual(query.apply(all, projectID: project), [b])
        query.picket = "пк"
        XCTAssertEqual(query.apply(all, projectID: project), [b,a])
        query.picket = ""; query.byPicket = true
        XCTAssertEqual(query.apply(all, projectID: project), [b,a])
        query.horizonID = nil; query.excavationID = nil
        XCTAssertEqual(query.apply(all, projectID: project), [b,a,c])
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(secondsFromGMT: 0)!
        query.startDate = Date(timeIntervalSince1970: 100000); query.endDate = Date(timeIntervalSince1970: 100001)
        XCTAssertEqual(query.apply(all, projectID: project, calendar: utc), [b,a]) // whole inclusive UTC day
        query.startDate = Date(timeIntervalSince1970: 172800)
        XCTAssertTrue(query.apply(all, projectID: project, calendar: utc).isEmpty)
        XCTAssertEqual(w.journal.observations, all) // Queries never mutate evidence.
    }
    func testUnitsNeverDescribeUnknownDrawingCoordinatesAsMeters() {
        XCTAssertEqual(MappingCoordinateText.header(xyUnits: "m"), "Координаты, м")
        XCTAssertEqual(MappingCoordinateText.header(xyUnits: "mm"), "Координаты · X/Y — мм · Z — м")
        for units in ["drawing", "unknown", ""] {
            XCTAssertEqual(MappingCoordinateText.header(xyUnits: units), "Координаты · X/Y — ед. чертежа · Z — м")
        }
    }
}
