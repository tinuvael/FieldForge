import XCTest
#if canImport(FieldForgeCore)
@testable import FieldForgeCore
#else
@testable import FieldForge
#endif

final class WedgeW1Tests: XCTestCase {
    private func input(_ dip: String = "45", _ direction: String = "90", north: GeographicReference = .magneticNorth) -> ManualOrientationInput {
        ManualOrientationInput(dipAngleText: dip, dipDirectionText: direction, reference: north, usesConventionalDipSide: dip == "90" && !direction.isEmpty)
    }
    private func joint(_ identifier: JointSetIdentifier, orientation: ManualOrientationInput? = nil) -> JointSetDraft {
        var value = JointSetDraft(identifier: identifier)
        value.representative = orientation ?? input()
        return value
    }
    func testArchRiseSymmetryContinuityAndTangency() throws {
        for b in [2.4, 5.0, 12.0] {
            let d = try WedgeDimensions(width: b, height: b * 0.8, length: 10)
            let arch = WedgeArch(d)
            XCTAssertEqual(d.archHeight, b / 3, accuracy: 1e-12)
            XCTAssertEqual(d.wallHeight, d.height - b / 3, accuracy: 1e-12)
            XCTAssertEqual(arch.arcs[1].point(.pi / 2).z, d.height, accuracy: 1e-12)
            // Independently solved rational r/B with R/B = 173/250, h/B = 1/3.
            XCTAssertEqual(arch.sideRadius / b, 451.0 / 1728, accuracy: 1e-12)
            XCTAssertEqual(arch.centralRadius / b, 0.692, accuracy: 1e-12)
            for i in 0..<2 {
                let first = arch.arcs[i], next = arch.arcs[i + 1]
                XCTAssertLessThan((first.point(first.end) - next.point(next.start)).length, 1e-12)
                XCTAssertLessThan((first.tangent(first.end) - next.tangent(next.start)).length, 1e-12)
            }
            XCTAssertEqual(arch.arcs[0].point(0).x, b / 2, accuracy: 1e-12)
            XCTAssertEqual(arch.arcs[0].point(0).z, d.wallHeight, accuracy: 1e-12)
            XCTAssertEqual(arch.arcs[0].tangent(0).z, 1)
            for step in 0...10 {
                let right = arch.arcs[0].point(arch.arcs[0].end * Double(step) / 10)
                let left = arch.arcs[2].point(.pi - arch.arcs[0].end * Double(step) / 10)
                XCTAssertEqual(right.x, -left.x, accuracy: 1e-12)
                XCTAssertEqual(right.z, left.z, accuracy: 1e-12)
            }
        }
    }
    func testDimensionsAndDecimalValidation() throws {
        for tuple in [(0.0, 3.0, 10.0), (-1, 3, 10), (3, 1, 10), (3, 0.5, 10), (3, 3, 0), (.nan, 3, 10), (3, .infinity, 10), (3, 3, .greatestFiniteMagnitude)] {
            XCTAssertThrowsError(try WedgeDimensions(width: tuple.0, height: tuple.1, length: tuple.2))
        }
        XCTAssertNoThrow(try WedgeDimensions(width: 3, height: 1.001, length: 10))
        XCTAssertEqual(WedgeInput.number(" 4,25 "), 4.25)
        XCTAssertEqual(WedgeInput.number("4.25"), 4.25)
        for value in ["", "NaN", "inf", "4,2.5"] { XCTAssertNil(WedgeInput.number(value)) }
        XCTAssertEqual(WedgeInput.azimuth("360"), 0)
        for value in ["-1", "361", "nan", ""] { XCTAssertNil(WedgeInput.azimuth(value)) }
    }
    func testClosedMeshFiniteVerticesIndicesAndOutwardWinding() throws {
        let d = try WedgeDimensions(width: 6, height: 5, length: 12)
        let mesh = WedgeArch(d).mesh()
        XCTAssertTrue(mesh.vertices.allSatisfy(\.isFinite))
        XCTAssertEqual(mesh.triangles.count % 3, 0)
        var edges: [String: (count: Int, balance: Int)] = [:]
        let center = Vector3(x: 0, y: 6, z: 2.5)
        for offset in stride(from: 0, to: mesh.triangles.count, by: 3) {
            let ids = Array(mesh.triangles[offset..<offset + 3]).map(Int.init)
            XCTAssertTrue(ids.allSatisfy { mesh.vertices.indices.contains($0) })
            let a = mesh.vertices[ids[0]], b = mesh.vertices[ids[1]], c = mesh.vertices[ids[2]]
            let normal = (b - a).cross(c - a)
            XCTAssertGreaterThan(normal.length, 0)
            XCTAssertGreaterThan(normal.dot(a - center), 0)
            for i in 0..<3 {
                let x = ids[i], y = ids[(i + 1) % 3], key = "\(min(x, y))/\(max(x, y))"
                let old = edges[key] ?? (0, 0)
                edges[key] = (old.count + 1, old.balance + (x < y ? 1 : -1))
            }
        }
        XCTAssertTrue(edges.values.allSatisfy { $0.count == 2 && $0.balance == 0 })
    }
    func testIndependentlyVerifiedOrientationAndSingularPlanes() throws {
        // Axis east, plane dips north at 45°. Down-dip vector is local (-1,0,-1)/sqrt(2).
        let n = try XCTUnwrap(WedgePlaneGeometry.normal(input: input("45", "0"), axis: 90))
        XCTAssertEqual(n.x, -sqrt(0.5), accuracy: 1e-12)
        XCTAssertEqual(n.y, 0, accuracy: 1e-12)
        XCTAssertEqual(n.z, sqrt(0.5), accuracy: 1e-12)
        XCTAssertEqual(n.dot(.init(x: -1, y: 0, z: -1)), 0, accuracy: 1e-12)
        XCTAssertEqual(WedgePlaneGeometry.normal(input: input("0", ""), axis: 30), .init(x: 0, y: 0, z: 1))
        let vertical = try XCTUnwrap(WedgePlaneGeometry.normal(input: input("90", "90"), axis: 0))
        XCTAssertEqual(vertical.x, 1, accuracy: 1e-12); XCTAssertEqual(vertical.z, 0, accuracy: 1e-12)
        XCTAssertNil(WedgePlaneGeometry.normal(input: input("90", ""), axis: 0))
        XCTAssertNil(WedgePlaneGeometry.intersection(n, n))
        let trace = try XCTUnwrap(WedgePlaneGeometry.intersection(n, vertical))
        XCTAssertEqual(trace.dot(n), 0, accuracy: 1e-12); XCTAssertEqual(trace.dot(vertical), 0, accuracy: 1e-12)
    }
    func testExactlyThreeValidSystemsAndNorthCompatibility() throws {
        let sets = [joint(.J1), joint(.J2), joint(.J3), joint(.J4, orientation: input("", ""))]
        let source = WedgeMappingSource(context: MappingContext(), pointID: UUID(), revisionID: nil, version: nil,
                                        title: "Draft", joints: sets.map { WedgeJoint(origin: .draft($0)) })
        XCTAssertEqual(source.validJoints.count, 3)
        XCTAssertEqual(try source.selectedJoints(source.initialSelection, axisNorth: .magneticNorth).count, 3)
        XCTAssertThrowsError(try source.selectedJoints(Set(source.initialSelection.prefix(2)), axisNorth: .magneticNorth))
        XCTAssertThrowsError(try source.selectedJoints(source.initialSelection, axisNorth: .trueNorth))
        XCTAssertThrowsError(try source.selectedJoints(source.initialSelection, axisNorth: .unknown))
        var mixed = sets; mixed[1].representative.reference = .gridNorth
        let mixedSource = WedgeMappingSource(context: source.context, pointID: source.id, revisionID: nil, version: nil,
                                             title: "Mixed", joints: mixed.map { WedgeJoint(origin: .draft($0)) })
        XCTAssertThrowsError(try mixedSource.selectedJoints(mixedSource.initialSelection, axisNorth: .magneticNorth))
        let four = WedgeMappingSource(context: source.context, pointID: source.id, revisionID: nil, version: nil,
                                     title: "Four", joints: (sets.prefix(3) + [joint(.J5)]).map { WedgeJoint(origin: .draft($0)) })
        XCTAssertTrue(four.initialSelection.isEmpty)
        XCTAssertThrowsError(try four.selectedJoints(Set(four.joints.map(\.id)), axisNorth: .magneticNorth))
        let two = WedgeMappingSource(context: source.context, pointID: source.id, revisionID: nil, version: nil,
                                    title: "Two", joints: Array(source.joints.prefix(2)))
        XCTAssertThrowsError(try two.selectedJoints(Set(two.joints.map(\.id)), axisNorth: .magneticNorth))
    }
    func testReadOnlySourceContextLatestRevisionAndDraftProvenance() throws {
        final class ReadOnlyStore: MappingStore {
            var value = MappingJournal()
            func load() throws -> MappingJournal { value }
            func save(_ journal: MappingJournal) throws { XCTFail("W1 must not write"); throw StorageError.writesBlocked }
        }
        let store = ReadOnlyStore(), p = UUID(), h = UUID(), e = UUID(), pointID = UUID(), revisionID = UUID()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        store.value.selection = MappingContext(projectID: p, horizonID: h, excavationID: e)
        func observation(id: UUID, excavation: UUID, dip: String) throws -> MappingObservation {
            MappingObservation(id: id, projectID: p, horizonID: h, excavationID: excavation, picket: "5", chainageMeters: 5,
                chainageOriginAndDirection: "manual", observedAt: now, observedTimeZoneID: "UTC", observedUTCOffsetSeconds: 0,
                createdAt: now, updatedAt: now, coordinates: nil, measurementIDs: [], notes: "",
                geology: MappingGeology(start: nil, end: nil, position: nil,
                    jointSets: [try joint(.J1, orientation: input(dip, "90")).record(now: now)], tectonicStructures: []))
        }
        let original = try observation(id: pointID, excavation: e, dip: "30")
        let effective = try observation(id: pointID, excavation: e, dip: "60")
        store.value.observations = [original, try observation(id: UUID(), excavation: UUID(), dip: "45")]
        store.value.revisions = [MappingObservationRevision(id: revisionID, observationID: pointID, version: 2, previousRevisionID: nil,
                                                           correctedAt: now, author: "Engineer", reason: "Correction", snapshot: effective)]
        var workflow = try MappingWorkflow(store: store)
        workflow.draft.jointSets = [joint(.J3)]
        let before = workflow.journal, draft = workflow.draft
        let sources = WedgeMappingSource.available(in: workflow)
        XCTAssertEqual(sources.count, 2)
        XCTAssertEqual(sources[0].pointID, draft.id); XCTAssertNil(sources[0].version)
        XCTAssertEqual(sources[0].joints.first?.origin, .draft(draft.jointSets[0]))
        XCTAssertEqual(sources[1].revisionID, revisionID); XCTAssertEqual(sources[1].version, 2)
        XCTAssertEqual(sources[1].joints.first?.origin, effective.geology?.jointSets.first.map { .saved($0) })
        XCTAssertEqual(sources[1].joints.first?.input.dipAngleText, "60")
        XCTAssertEqual(workflow.journal, before); XCTAssertEqual(workflow.draft, draft)
    }
    func testDistanceResultCancelAndManualCorrection() {
        var field = WedgeDimensionInput(); field.edit("4,5")
        field.accept(nil); XCTAssertEqual(field.text, "4,5")
        let result = DistanceResult(metres: 4.123456789, source: .lidarDepth)
        field.accept(result); XCTAssertEqual(WedgeInput.number(field.text), result.metres); XCTAssertFalse(field.manuallyEdited)
        field.edit("4,2"); XCTAssertEqual(field.measurement, result); XCTAssertTrue(field.manuallyEdited)
        field.accept(nil); XCTAssertEqual(field.text, "4,2")
    }
    func testDedicatedAxisHeadingProjectionAndQualityGates() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var sample = SensorSample(timestamp: now, uptime: 1, source: .coreMotion, referenceFrame: .magneticNorthZVertical,
            rotation: .init(row1: .init(x: 0, y: -1, z: 0), row2: .init(x: 1, y: 0, z: 0), row3: .init(x: 0, y: 0, z: 1)),
            quaternion: .init(x: 0, y: 0, z: sqrt(0.5), w: sqrt(0.5)), gravity: .init(x: 0, y: 0, z: -1),
            userAcceleration: .init(x: 0, y: 0, z: 0), rotationRate: .init(x: 0, y: 0, z: 0),
            magneticField: .init(x: 40, y: 0, z: 0), magneticAccuracy: .high)
        XCTAssertEqual(WedgePlaneGeometry.axisHeading(sample: sample, now: now), 0)
        XCTAssertNil(WedgePlaneGeometry.axisHeading(sample: sample, now: now.addingTimeInterval(3)))
        sample.magneticAccuracy = .low
        XCTAssertNil(WedgePlaneGeometry.axisHeading(sample: sample, now: now))
    }
}
