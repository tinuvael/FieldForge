import XCTest
#if canImport(FieldForgeCore)
@testable import FieldForgeCore
#else
@testable import FieldForge
#endif

final class MappingJournalQueryTests: XCTestCase {
    @MainActor func testCommittedIndexesMatchExistingQueriesAndLimitedRenderWork() async throws {
        let journal = try MappingStorageBenchmarkTests.fixture(100)
        let snapshot = await Task.detached {
            XCTAssertFalse(Thread.isMainThread)
            return MappingCommittedSnapshot(journal)
        }.value
        XCTAssertEqual(snapshot.journal, journal)
        XCTAssertEqual(snapshot.effectiveObservations, journal.effectiveObservations)
        XCTAssertNil(snapshot.observation(id: UUID()))
        XCTAssertEqual(snapshot.observationCount(projectID: nil), 0)
        XCTAssertTrue(snapshot.observations(context: MappingContext()).isEmpty)
        for observation in journal.effectiveObservations {
            XCTAssertEqual(snapshot.observation(id: observation.id), observation)
            XCTAssertEqual(snapshot.latestRevisions[observation.id], journal.history(for: observation.id).last)
            XCTAssertEqual(snapshot.measurements(for: observation), journal.measurements(for: observation))
        }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .gmt
        for project in journal.projects {
            let records = journal.effectiveObservations.filter { $0.projectID == project.id }
            XCTAssertEqual(snapshot.observations(projectID: project.id), records)
            XCTAssertEqual(snapshot.observationCount(projectID: project.id), records.count)
            for horizon in journal.horizons where horizon.projectID == project.id {
                for excavation in journal.excavations where excavation.projectID == project.id {
                    let context = MappingContext(projectID: project.id, horizonID: horizon.id, excavationID: excavation.id)
                    XCTAssertEqual(snapshot.observations(context: context), records.filter {
                        $0.horizonID == horizon.id && $0.excavationID == excavation.id
                    })
                    var query = MappingJournalQuery(horizonID: horizon.id, excavationID: excavation.id)
                    for search in ["", "2", "ПК", "missing"] {
                        query.picket = search
                        query.byPicket = search.isEmpty
                        query.startDate = records.first?.observedAt
                        query.endDate = records.last?.observedAt
                        XCTAssertEqual(query.apply(snapshot.observations(projectID: project.id), projectID: project.id, calendar: calendar),
                                       query.apply(journal.effectiveObservations, projectID: project.id, calendar: calendar))
                    }
                }
            }
        }
        for plan in journal.plans {
            // Exact pre-A6 overlay query, including source lookup and compatibility.
            let expected = journal.effectiveObservations.filter { point in
                guard let horizon = journal.horizons.first(where: { $0.id == plan.horizonID }),
                      point.projectID == horizon.projectID, point.horizonID == plan.horizonID,
                      point.coordinates?.x != nil, point.coordinates?.y != nil,
                      let source = journal.plans.first(where: { $0.id == point.coordinates?.planID }) else { return false }
                return PlanCoordinateCompatibility.compatible(source, plan, plans: journal.plans)
            }
            XCTAssertEqual(snapshot.points(on: plan, excavationID: nil), expected)
            for excavation in journal.excavations {
                XCTAssertEqual(snapshot.points(on: plan, excavationID: excavation.id), expected.filter { $0.excavationID == excavation.id })
            }
        }
        // Optional, small paired diagnostic; correctness never depends on timings.
        guard ProcessInfo.processInfo.environment["FIELD_FORGE_UI_QUERIES_A6"] == "1" else { return }
        let projectID = journal.projects[0].id, query = MappingJournalQuery()
        let expected = query.apply(journal.effectiveObservations, projectID: projectID)
        func sample(_ name: String, _ body: () -> ([MappingObservation], Int, Bool, Int)) {
            var times: [Double] = []
            for _ in 0..<30 {
                let start = DispatchTime.now().uptimeNanoseconds
                let result = body()
                times.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
                XCTAssertEqual(result.0, expected)
                XCTAssertEqual(result.1, expected.count)
                XCTAssertEqual(result.2, expected.isEmpty)
                XCTAssertEqual(result.3, snapshot.observationCount(projectID: projectID))
            }
            print("A6,100,\(name),30,median_ms=\(times.sorted()[15])")
        }
        sample("journal-render-before") {
            let count = query.apply(journal.effectiveObservations, projectID: projectID).count
            let empty = query.apply(journal.effectiveObservations, projectID: projectID).isEmpty
            let total = journal.effectiveObservations.filter { $0.projectID == projectID }.count
            return (query.apply(journal.effectiveObservations, projectID: projectID), count, empty, total)
        }
        sample("journal-render-after") {
            let records = query.apply(snapshot.observations(projectID: projectID), projectID: projectID)
            return (records, records.count, records.isEmpty, snapshot.observationCount(projectID: projectID))
        }
        let start = DispatchTime.now().uptimeNanoseconds
        let rebuilt = await Task.detached { MappingCommittedSnapshot(journal) }.value
        print("A6,100,index-build-and-task-hop,1,ms=\(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)")
        XCTAssertEqual(rebuilt.effectiveObservations, snapshot.effectiveObservations)
    }

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
