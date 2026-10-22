import XCTest
import Darwin
#if canImport(FieldForgeCore)
@testable import FieldForgeCore
#else
@testable import FieldForge
#endif

/// Opt-in evidence for #33; no performance thresholds or application-data paths.
@MainActor final class MappingStorageBenchmarkTests: XCTestCase {
    private static let epoch = Date(timeIntervalSince1970: 1_700_000_000)
    private static func id(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012llx", Int64(value)))!
    }

    /// Fixed-density profile: two originals/point; J1–J5, Q/RMR and a photo every
    /// tenth point; two corrections every twentieth point. No random IDs/dates.
    private static func fixture(_ count: Int) throws -> MappingJournal {
        var journal = MappingJournal()
        for group in 0..<4 {
            let p = id(1 + group), h = id(11 + group), e = id(21 + group)
            journal.projects.append(MappingProject(id: p, name: "Synthetic project \(group)"))
            journal.horizons.append(MappingHorizon(id: h, projectID: p, name: "Synthetic horizon",
                elevationMeters: nil, elevationDatum: "unknown"))
            journal.excavations.append(MappingExcavation(id: e, projectID: p,
                name: "Synthetic excavation", horizonIDs: [h]))
            journal.plans.append(MappingPlanReference(id: id(31 + group), horizonID: h,
                attachmentID: id(41 + group), version: "1", file: ManagedPlanFile(
                    originalFilename: "reference-only.dxf", sha256: String(repeating: "a", count: 64),
                    byteCount: 100, importedAt: epoch, units: .meters, crs: "synthetic-local",
                    axes: "WCS XY", unitDeclaration: "userConfirmedAtImport", insertionUnits: nil)))
        }
        journal.selection = MappingContext(projectID: id(1), horizonID: id(11), excavationID: id(21))
        for index in 0..<count {
            let base = 1_000 + index * 20, group = index % 4
            let p = id(1 + group), h = id(11 + group), e = id(21 + group)
            let time = epoch.addingTimeInterval(Double(index * 60))
            let input = ManualOrientationInput(dipAngleText: "45.125", dipDirectionText: "120", reference: .gridNorth)
            let manual = try input.observation(notes: "Synthetic original", id: id(base + 1), timestamp: time)
            let sensor = Measurement.process(MockSensorProvider.sample(dip: 55, direction: 230, timestamp: time), id: id(base + 2))
            journal.measurements += [manual, sensor]
            var sets: [InterpretedJointSet] = []
            var ratings: MappingRatings?
            if index % 10 == 0 {
                for (offset, name) in JointSetIdentifier.allCases.enumerated() {
                    var set = JointSetDraft(identifier: name, id: id(base + 3 + offset))
                    set.representative = input; set.measurementIDs = [manual.id, sensor.id]
                    set.spacing = "0.5"; set.author = "Synthetic interpreter"
                    sets.append(try set.record(now: time))
                }
                var q = BartonQInput(); q.rqd = "80"; q.rqdSource = .coreMeasured
                q.location = .ordinary; q.contact = .wall; q.assessmentSource = "Synthetic log"
                q.jn.select("F", parameter: .jn); q.jr.select("B", parameter: .jr)
                q.ja.select("C", parameter: .ja); q.jw.select("A", parameter: .jw); q.srf.select("G", parameter: .srf)
                var rmr = RMR89Input(); rmr.rqd = "80"; rmr.source = "Synthetic input only"
                ratings = MappingRatings(bartonQ: try BartonQAssessment(input: q, now: time),
                    rmr89: try RMR89Assessment(input: rmr, now: time))
            }
            let point = MappingObservation(id: id(base), projectID: p, horizonID: h, excavationID: e,
                picket: String(index), chainageMeters: Double(index * 10), chainageOriginAndDirection: "synthetic origin; increasing +X",
                observedAt: time, observedTimeZoneID: "UTC", observedUTCOffsetSeconds: 0,
                createdAt: time, updatedAt: time,
                coordinates: MappingCoordinates(x: Double(index), y: Double(group), z: nil,
                    crs: "synthetic-local", axes: "WCS XY", units: "m", source: "plan",
                    provenance: "synthetic plan selection; accuracy unknown", planID: id(31 + group)),
                measurementIDs: [manual.id, sensor.id], notes: "Synthetic point \(index)",
                geology: sets.isEmpty ? nil : MappingGeology(start: nil, end: nil, position: .roof,
                    jointSets: sets, tectonicStructures: []), ratings: ratings, picketConvention: .tenMeters)
            journal.observations.append(point)
            if index % 20 == 0 {
                var previous: UUID?
                for version in 2...3 {
                    var draft = MappingCorrectionDraft(observation: point, previousRevisionID: previous, measurements: [manual, sensor])
                    draft.reason = "Synthetic correction \(version)"; draft.fields.notes = "Corrected \(version)"
                    let correctedAt = time.addingTimeInterval(Double(version))
                    let revision = MappingObservationRevision(id: id(base + 8 + version), observationID: point.id,
                        version: version, previousRevisionID: previous, correctedAt: correctedAt,
                        author: "Synthetic interpreter", reason: draft.reason, snapshot: try draft.snapshot(now: correctedAt))
                    journal.revisions.append(revision); previous = revision.id
                }
            }
            if index % 10 == 0 {
                journal.photoAttachments.append(PhotoAttachment(id: id(base + 12), originalFilename: "reference-only.jpg",
                    sha256: String(repeating: "b", count: 64), byteCount: 100, format: "public.jpeg", mimeType: "image/jpeg",
                    pixelWidth: 2, pixelHeight: 2, orientation: 1, representation: "synthetic reference only"))
                let context = PhotoContext(projectID: p, horizonID: h, excavationID: e, pointID: point.id,
                    pointRevisionID: previousRevisionID(journal, point: point), pointVersion: index % 20 == 0 ? 3 : 1)
                journal.photos.append(PhotoObservation(id: id(base + 13), attachmentID: id(base + 12), context: context,
                    source: .files, importedAt: time, capturedAt: nil, captureTimeText: nil,
                    captureTimeProvenance: "synthetic; capture time unknown", metadata: PhotoMetadata(name: "Synthetic photo")))
            }
        }
        return journal
    }

    private static func previousRevisionID(_ journal: MappingJournal, point: MappingObservation) -> UUID {
        journal.history(for: point.id).last?.id ?? point.id
    }

    private func measure<T>(_ size: Int, _ name: String, repetitions: Int,
                            _ body: () throws -> T, check: (T) throws -> Void) throws {
        var samples: [Double] = []
        for _ in 0..<repetitions {
            let elapsed = try autoreleasepool { () throws -> Double in
                let start = DispatchTime.now().uptimeNanoseconds
                let result = try body()
                let end = DispatchTime.now().uptimeNanoseconds
                try check(result) // Consume/verify results outside the timed interval.
                return Double(end - start) / 1_000_000
            }
            samples.append(elapsed)
        }
        let sorted = samples.sorted(), mid = sorted.count / 2
        let median = sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
        let p95 = repetitions >= 100 ? String(format: "%.3f", sorted[Int(ceil(Double(repetitions) * 0.95)) - 1]) : "n/a"
        print("BASELINE,\(size),\(name),\(repetitions),\(String(format: "%.3f", median)),\(p95),\(String(format: "%.3f", sorted.first!)),\(String(format: "%.3f", sorted.last!))")
        fflush(stdout)
    }

    func testStorageBaseline() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["FIELD_FORGE_STORAGE_BENCHMARKS"] == "1",
            "Opt in: FIELD_FORGE_STORAGE_BENCHMARKS=1 swift test -c release --filter MappingStorageBenchmarkTests")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FieldForge-storage-benchmark-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        print("BASELINE environment: \(ProcessInfo.processInfo.operatingSystemVersionString); CPUs=\(ProcessInfo.processInfo.processorCount); RAM=\(ProcessInfo.processInfo.physicalMemory); schema=\(MappingJournal.currentSchemaVersion)")
        print("BASELINE,size,operation,n,median_ms,p95_ms,min_ms,max_ms")
        for size in [100, 1_000, 5_000] {
            let journal = try Self.fixture(size)
            XCTAssertEqual(journal, try Self.fixture(size))
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
            let bytes = try encoder.encode(journal)
            let url = root.appendingPathComponent("\(size).json")
            try bytes.write(to: url, options: .atomic)
            print("BASELINE fixture: N=\(size), R=\(journal.revisions.count), M=\(journal.measurements.count), photos=\(journal.photos.count), bytes=\(bytes.count)")
            try measure(size, "read+decode", repetitions: 10, {
                try JSONDecoder().decode(MappingJournal.self, from: Data(contentsOf: url))
            }, check: { XCTAssertEqual($0, journal) })
            try measure(size, "decode", repetitions: 10, {
                try JSONDecoder().decode(MappingJournal.self, from: bytes)
            }, check: { XCTAssertEqual($0, journal) })
            try measure(size, "cold-store-load", repetitions: 3, {
                try FileMappingStore(url: url).load()
            }, check: { XCTAssertEqual($0, journal) })
            try measure(size, "validate-full", repetitions: 3, { try journal.validate() }, check: { _ in })
            try measure(size, "validate-base-graph", repetitions: 3, {
                try journal.validateGraph(includingRevisions: false)
            }, check: { _ in })
            try measure(size, "validate-revisions", repetitions: 3, { try journal.validateRevisions() }, check: { _ in })
            let effective = journal.effectiveObservations
            try measure(size, "effective-all", repetitions: 100, { journal.effectiveObservations },
                check: { XCTAssertEqual($0, effective) })
            let lastID = journal.observations.last!.id
            try measure(size, "effective-single-last", repetitions: 100, { journal.effectiveObservation(id: lastID) },
                check: { XCTAssertEqual($0?.id, lastID) })
            var query = MappingJournalQuery(); query.byPicket = true
            try measure(size, "query-project-sort", repetitions: 100, { query.apply(effective, projectID: Self.id(1)) },
                check: { XCTAssertEqual($0.count, size / 4) })
            query.horizonID = Self.id(11); query.excavationID = Self.id(21); query.picket = "2"
            query.startDate = Self.epoch; query.endDate = Self.epoch.addingTimeInterval(Double(size * 60))
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            let expected = query.apply(effective, projectID: Self.id(1), calendar: calendar)
            try measure(size, "effective+query-filter", repetitions: 100, {
                query.apply(journal.effectiveObservations, projectID: Self.id(1), calendar: calendar)
            }, check: { XCTAssertEqual($0, expected); XCTAssertFalse($0.isEmpty) })
            try measure(size, "append-only-membership", repetitions: 3, {
                journal.observations.allSatisfy { journal.observations.contains($0) } &&
                journal.measurements.allSatisfy { journal.measurements.contains($0) } &&
                journal.revisions.allSatisfy { journal.revisions.contains($0) } &&
                journal.photos.allSatisfy { journal.photos.contains($0) } &&
                journal.photoAttachments.allSatisfy { journal.photoAttachments.contains($0) }
            }, check: { XCTAssertTrue($0) })
            try measure(size, "encode", repetitions: 10, { try encoder.encode(journal) },
                check: { XCTAssertEqual($0, bytes) })
            let diskURL = root.appendingPathComponent("\(size)-disk.json")
            try measure(size, "atomic-json+previous", repetitions: 100, {
                try bytes.write(to: diskURL.appendingPathExtension("previous"), options: .atomic)
                try bytes.write(to: diskURL, options: .atomic)
            }, check: { _ in XCTAssertEqual(try Data(contentsOf: diskURL), bytes) })
            // Each write metric starts from the same baseline; three successive commits
            // add at most three points/revisions. Initialization is outside timing.
            for operation in ["save-no-op", "save-new", "save-revision", "switch-context"] {
                let writeURL = root.appendingPathComponent("\(size)-\(operation).json")
                try bytes.write(to: writeURL, options: .atomic)
                let store = FileMappingStore(url: writeURL)
                var workflow = try MappingWorkflow(store: store)
                var iteration = 0
                var expectedPreviousBytes = bytes
                try measure(size, operation, repetitions: 3, {
                    iteration += 1
                    switch operation {
                    case "save-no-op": try store.save(workflow.journal)
                    case "save-new":
                        var draft = MappingDraft(id: Self.id(500_000 + iteration))
                        draft.picket = String(size + iteration); draft.timeZoneID = "UTC"
                        try draft.addMeasurement(journal.measurements[0].manualInput!.observation(
                            id: Self.id(600_000 + iteration), timestamp: Self.epoch))
                        workflow.draft = draft; try workflow.save(now: Self.epoch)
                    case "save-revision":
                        var draft = try workflow.correction(for: journal.observations[0].id)
                        draft.reason = "Benchmark correction"; draft.fields.notes = "Benchmark \(iteration)"
                        try workflow.saveCorrection(draft, now: Self.epoch.addingTimeInterval(Double(iteration + 10)))
                    default:
                        let group = iteration % 2
                        try workflow.requestContext(MappingContext(projectID: Self.id(1 + group),
                            horizonID: Self.id(11 + group), excavationID: Self.id(21 + group)))
                    }
                }, check: { _ in
                    let savedBytes = try Data(contentsOf: writeURL)
                    let saved = try JSONDecoder().decode(MappingJournal.self, from: savedBytes)
                    XCTAssertEqual(saved, workflow.journal)
                    XCTAssertEqual(saved.observations.count, size + (operation == "save-new" ? iteration : 0))
                    XCTAssertEqual(saved.revisions.count, journal.revisions.count + (operation == "save-revision" ? iteration : 0))
                    XCTAssertEqual(try Data(contentsOf: store.backupURL), expectedPreviousBytes)
                    expectedPreviousBytes = savedBytes
                })
                XCTAssertEqual(try JSONDecoder().decode(MappingJournal.self, from: Data(contentsOf: store.backupURL)).schemaVersion, 8)
            }
            XCTAssertEqual(try Data(contentsOf: url), bytes)
            var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
            print("BASELINE process-peak-rss-bytes through N=\(size): \(usage.ru_maxrss)")
        }
    }
}
