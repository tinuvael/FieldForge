import XCTest
#if canImport(FieldForgeCore)
@testable import FieldForgeCore
#else
@testable import FieldForge
#endif

@MainActor final class FinalFieldPolishTests: XCTestCase {
    /// Hoek, Practical Rock Engineering, Rock mass classification pp. 9–10:
    /// 12 + 13 + 10 + (4 + 4 + 3 + 6 + 5) + 7 = 64 BASIC.
    /// The published adjusted example is 59, after -5; we never apply that correction.
    static func referenceInput() -> RMR89Input {
        var input = RMR89Input(); input.strengthTest = .pointLoadIs50
        input.strengthMPa = "8"; input.rqd = "70"; input.spacingMeters = "0.3"
        input.persistenceMeters = "2"; input.apertureMillimeters = "0.5"
        input.basicSelections = ["strength": "is50-1", "rqd": "rqd-2", "spacing": "spacing-2",
            "persistence": "persistence-1", "aperture": "aperture-2", "roughness": "roughness-2",
            "infill": "infill-0", "weathering": "weathering-1", "groundwater": "groundwater-2"]
        return input
    }
    func testPublishedReferenceBasicIs64WithoutOrientationAdjustment() throws {
        var input = Self.referenceInput()
        for application in RMREngineeringApplication.allCases {
            input.application = application; input.orientationDescription = "Неблагоприятная"
            let result = try input.basicEvaluation()
            XCTAssertEqual(result.value, 64); XCTAssertEqual(result.components["condition"], 22)
            XCTAssertEqual(result.rockClass, "II — хорошее качество")
            XCTAssertEqual(result.missing, [])
        }
    }
    func testEveryPublishedRatingRowAndStrengthBasis() {
        let expected: [RMR89Parameter: [Int]] = [.strength: [15, 12, 7, 4, 2, 1, 0], .rqd: [20, 17, 13, 8, 3], .spacing: [20, 15, 10, 8, 5], .persistence: [6, 4, 2, 1, 0], .aperture: [6, 5, 4, 1, 0], .roughness: [6, 5, 3, 1, 0], .infill: [6, 4, 2, 2, 0], .weathering: [6, 5, 3, 1, 0], .groundwater: [15, 10, 7, 4, 0], .overallCondition: [30, 25, 20, 10, 0]]
        for (parameter, ratings) in expected { XCTAssertEqual(parameter.choices(test: .ucs).map(\.rating), ratings) }
        XCTAssertEqual(RMR89Parameter.strength.choices(test: .pointLoadIs50).map(\.rating), [15, 12, 7, 4])
        XCTAssertTrue(RMR89Parameter.strength.choices(test: nil).isEmpty)
    }
    func testClassificationBoundariesAndInvalidValues() {
        for (value, prefix) in [(0,"V"),(20,"V"),(21,"IV"),(40,"IV"),(41,"III"),(60,"III"),(61,"II"),(80,"II"),(81,"I"),(100,"I")] {
            XCTAssertTrue(RMR89BasicEvaluation.classification(value)!.hasPrefix(prefix + " —"))
        }
        XCTAssertNil(RMR89BasicEvaluation.classification(-1)); XCTAssertNil(RMR89BasicEvaluation.classification(101))
    }
    func testMissingCategoriesNeverBecomeZeroOrFavorableDefaults() throws {
        let complete = Self.referenceInput()
        for key in complete.basicSelections!.keys {
            var input = complete; input.basicSelections?[key] = nil
            XCTAssertNil(try input.basicEvaluation().value); XCTAssertFalse(try input.basicEvaluation().missing.isEmpty)
        }
        XCTAssertNil(try RMR89Input().basicEvaluation().value)
        var input = complete; input.strengthTest = .ucs
        XCTAssertThrowsError(try input.basicEvaluation()) // Is50 category is not UCS.
        input = complete; input.strengthMPa = "0.9"
        XCTAssertThrowsError(try input.basicEvaluation()) // No low Is50 conversion.
        input = complete; input.basicSelections?["unknown"] = "1"
        XCTAssertThrowsError(try input.basicEvaluation())
    }
    func testMeasuredBoundaryAgreementAndExplicitSharedEndpoints() throws {
        var input = Self.referenceInput()
        for (raw, category) in [("4", "is50-1"), ("4", "is50-2"), ("10", "is50-1"), ("10.000001", "is50-0"), ("1", "is50-3")] {
            input.strengthMPa = raw; input.basicSelections?["strength"] = category
            XCTAssertNotNil(try input.basicEvaluation().value)
        }
        input = Self.referenceInput(); input.apertureMillimeters = "0"
        XCTAssertThrowsError(try input.basicEvaluation())
        input.basicSelections?["aperture"] = "aperture-0"
        XCTAssertEqual(try input.basicEvaluation().value, 66)
        input.rqd = "100.01"; XCTAssertThrowsError(try input.basicEvaluation())
    }
    func testFilledDiscontinuitiesRequireExplicitA4InsteadOfEAddition() throws {
        var input = Self.referenceInput(); input.basicSelections?["infill"] = "infill-4"
        XCTAssertNil(try input.basicEvaluation().value)
        input.basicSelections?["overallCondition"] = "overallCondition-4"
        XCTAssertEqual(try input.basicEvaluation().value, 42)
        XCTAssertEqual(try input.basicEvaluation().components["condition"], 0)
        input.basicSelections?["roughness"] = "roughness-0"
        XCTAssertEqual(try input.basicEvaluation().value, 42) // Gouge masks roughness.
        input.basicSelections?["overallCondition"] = "overallCondition-0"
        XCTAssertThrowsError(try input.basicEvaluation())
        input.basicSelections?["infill"] = "infill-2"
        XCTAssertNil(try input.basicEvaluation().value) // Hard >5 mm is not uniquely covered by A.4.
    }
    func testCalculatedSnapshotRoundTripRejectsTamperingAndKeepsLegacyJSON() throws {
        let assessment = try RMR89Assessment(input: Self.referenceInput(), now: Date(timeIntervalSince1970: 100))
        let data = try JSONEncoder().encode(assessment)
        let reopened = try JSONDecoder().decode(RMR89Assessment.self, from: data)
        try reopened.validate(); XCTAssertEqual(reopened, assessment)
        XCTAssertEqual(reopened.method, RMR89Assessment.calculatedVersion)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var calculation = json["calculation"] as! [String: Any]; calculation["value"] = 65; json["calculation"] = calculation
        XCTAssertThrowsError(try JSONDecoder().decode(RMR89Assessment.self, from: JSONSerialization.data(withJSONObject: json)).validate())
        let legacy = #"{"method":"Bieniawski-RMR89/input-only-v1","revision":1,"assessedAt":0,"input":{"strengthMPa":"","strengthEvidence":"Исходный журнал","rqd":"","rqdEvidence":"","spacingMeters":"","persistenceMeters":"","apertureMillimeters":"","roughness":"","infill":"","weathering":"","groundwater":"","inflowLitersPerMinutePer10m":"","waterPressureRatio":"","orientationDescription":"","source":"Архив","assessor":"","missingReason":""},"missing":["Прочность","RQD","Расстояние","Протяжённость","Раскрытие","Шероховатость","Заполнитель","Выветрелость","Ориентация","Подземные воды","Метод испытания прочности","Инженерное применение"]}"#
        let old = try JSONDecoder().decode(RMR89Assessment.self, from: Data(legacy.utf8))
        try old.validate(); XCTAssertNil(old.calculation); XCTAssertNil(old.input.basicSelections)
        XCTAssertEqual(old.input.strengthEvidence, "Исходный журнал")
    }
    func testCalculatedCorrectionPreservesOriginalsAndReloadsCurrentJournal() throws {
        let (store, initial, original) = try P33RevisionTests().seed(); var workflow = initial
        var correction = try workflow.correction(for: original.id)
        correction.fields.rmr89 = Self.referenceInput(); correction.reason = "Выбраны категории RMR89"
        let revision = try workflow.saveCorrection(correction)
        XCTAssertEqual(revision.snapshot.ratings?.rmr89?.calculation?.value, 64)
        XCTAssertEqual(workflow.journal.observations, [original]); XCTAssertEqual(workflow.journal.measurements, initial.journal.measurements)
        XCTAssertEqual(original.ratings?.rmr89?.method, RMR89Assessment.version)
        let journal = try JSONDecoder().decode(MappingJournal.self, from: JSONEncoder().encode(workflow.journal))
        try journal.validate(); store.value = journal
        XCTAssertEqual(try MappingWorkflow(store: store).observations, [revision.snapshot])
    }
    func testFieldSnapshotAndOneDefaultXLSXPreserveRawPrecisionAndRelationships() throws {
        let (_, initial, original) = try P33RevisionTests().seed(); var workflow = initial
        var correction = try workflow.correction(for: original.id)
        correction.fields.x = "123456.12345678912"; correction.fields.y = "-0.123456789123456"
        correction.fields.rmr89 = Self.referenceInput(); correction.reason = "Полевой экспорт"
        _ = try workflow.saveCorrection(correction)
        let before = workflow.journal
        let selection = MappingCSVExportTests().selection(original, "2023-11-14T12:00:00Z")
        let snapshot = try MappingCSVExport.prepare(journal: before, selection: selection)
        XCTAssertEqual(snapshot.fieldTables.map(\.name), ["Наблюдения", "Системы трещин", "Тектоника", "Рейтинги массива", "Фотографии", "field_links"])
        for table in snapshot.fieldTables { XCTAssertTrue(table.rows.allSatisfy { $0.count == table.columns.count }, table.name) }
        let field = snapshot.fieldTables[0], row = try XCTUnwrap(field.rows.first)
        if case .number(let value) = row[field.columns.firstIndex(of: "X")!] { XCTAssertEqual(value, 123456.12345678912) } else { XCTFail("Numeric X") }
        if case .integer(let value) = row[field.columns.firstIndex(of: "RMR89 базовый")!] { XCTAssertEqual(value, 64) } else { XCTFail("Numeric RMR") }
        let files = try MappingExportFiles.write(snapshot); defer { files.cleanup() }
        XCTAssertEqual(files.urls.count, 1); XCTAssertEqual(files.urls[0].pathExtension, "xlsx")
        XCTAssertEqual(workflow.journal, before)
        XCTAssertEqual(EngineeringDisplay.coordinate(123456.12345678912), "123456,1")
    }
    func testRepresentativeWorkbookFixtureWhenRequested() throws {
        guard let path = ProcessInfo.processInfo.environment["FF_FINAL_EXPORT_FIXTURE_DIR"] else { throw XCTSkip("Opt-in independent workbook fixture") }
        let (_, initial, original) = try P33RevisionTests().seed(); var workflow = initial
        try workflow.updateProject(id: original.projectID, name: "Рудник Северный")
        try workflow.updateExcavation(id: original.excavationID, name: "Штрек Восточный № 3", horizonIDs: [original.horizonID])
        var correction = try workflow.correction(for: original.id)
        correction.fields.x = "123456.12345678912"; correction.fields.y = "-0.123456789123456"
        correction.fields.rmr89 = Self.referenceInput(); correction.reason = "Полевой журнал"
        correction.fields.notes = "Кварцевая жила; угол 45°; μ/µ; раскрытие ≤1 мм.\n=1+1 — буквальная заметка"
        for id in [JointSetIdentifier.J3, .J4, .J5] {
            var joint = JointSetDraft(identifier: id)
            joint.representative = ManualOrientationInput(dipAngleText: "45.12345678912345", dipDirectionText: "285.125", reference: .magneticNorth)
            joint.roughness = "Шероховатая"; joint.infill = "Кальцит ≤1 мм"
            correction.fields.jointSets.append(joint)
        }
        _ = try workflow.saveCorrection(correction)
        let attachment = PhotoAttachment(id: UUID(), originalFilename: "Фото штрека №1.jpg", sha256: String(repeating: "a", count: 64), byteCount: 100, format: "public.jpeg", mimeType: "image/jpeg", pixelWidth: 2, pixelHeight: 2, orientation: 1, representation: "received bytes")
        let context = PhotoContext(projectID: original.projectID, horizonID: original.horizonID, excavationID: original.excavationID,
            pointID: original.id, pointRevisionID: original.id, pointVersion: 1, locationBasis: .unknownBeforeFirstSave)
        let photo = PhotoObservation(id: UUID(), attachmentID: attachment.id, context: context, source: .files, importedAt: original.observedAt, capturedAt: nil, captureTimeText: nil, captureTimeProvenance: "unknown", metadata: PhotoMetadata(name: "=1+1 Фото", description: "Кровля штрека"))
        try workflow.registerPhoto(PhotoImportOperation(version: 2, photo: photo, attachment: attachment))
        for offset in 1...2 {
            workflow.draft.picket = offset == 1 ? "12+1,8" : "13+2,5"
            workflow.draft.observedAtOverride = original.observedAt.addingTimeInterval(Double(offset) * 86400)
            workflow.draft.notes = offset == 1 ? "Трещины, заполненные кальцитом ≤1 мм" : "Неизвестные значения оставлены пустыми"
            if offset == 1 {
                workflow.draft.rmr89.source = "Старый ввод без расчёта"
                workflow.draft.bartonQ = original.ratings!.bartonQ!.input
            }
            _ = try workflow.save()
        }
        let before = workflow.journal
        let selection = MappingExportSelection(projectID: original.projectID, firstDay: original.observedAt,
            lastDay: original.observedAt.addingTimeInterval(2 * 86400), timeZoneID: "Asia/Almaty")
        let snapshot = try MappingCSVExport.prepare(journal: before, selection: selection)
        XCTAssertEqual(snapshot.pointCount, 3)
        for table in snapshot.fieldTables { XCTAssertTrue(table.rows.allSatisfy { $0.count == table.columns.count }, table.name) }
        let files = try MappingExportFiles.write(snapshot); defer { files.cleanup() }
        let root = URL(fileURLWithPath: path); try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(contentsOf: files.urls[0]).write(to: root.appendingPathComponent("FieldForge-Mapping.xlsx"))
        let advanced = try MappingExportFiles.write(snapshot, showTechnicalSheets: true); defer { advanced.cleanup() }
        try Data(contentsOf: advanced.urls[0]).write(to: root.appendingPathComponent("FieldForge-Technical.xlsx"))
        var expected: [String: Any] = [:]
        for table in snapshot.tables + snapshot.fieldTables {
            let field = snapshot.fieldTables.prefix(5).contains { $0.name == table.name }
            expected[table.name] = ["columns": table.columns, "rows": table.rows.map { row in row.map { value -> [String: Any] in
                switch value {
                case .text(let text): return ["type": "s", "value": text]
                case .number(let value):
                    guard let value else { return ["type": "blank"] }
                    let encoded = try! MappingXLSXExport.numericText(value)
                    return ["type": field || !encoded.isText ? "n" : "s", "value": field || !encoded.isText ? value as Any : encoded.value as Any]
                case .integer(let value): return value.map { ["type": "n", "value": $0] } ?? ["type": "blank"]
                case .timestamp(let date):
                    guard let date else { return ["type": "blank"] }
                    return field ? ["type": "d", "value": date.timeIntervalSince1970 + Double(TimeZone(identifier: selection.timeZoneID)!.secondsFromGMT(for: date))] : ["type": "s", "value": MappingCSVExport.iso(date)]
                case .empty: return ["type": "blank"]
                }
            } }]
        }
        try JSONSerialization.data(withJSONObject: expected, options: [.prettyPrinted, .sortedKeys]).write(to: root.appendingPathComponent("expected.json"))
        XCTAssertEqual(workflow.journal, before)
    }
}
