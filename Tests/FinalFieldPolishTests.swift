import XCTest
#if canImport(FieldForgeCore)
@testable import FieldForgeCore
#else
@testable import FieldForge
#endif

@MainActor final class FinalFieldPolishTests: XCTestCase {
    /// Hoek, Practical Rock Engineering, Rock mass classification pp. 8–11:
    /// 12 + 13 + 10 + (4 + 4 + 3 + 6 + 5) + 7 = 64 BASIC.
    /// The published adjusted example is 59, after a Table 4.1 B correction of −5.
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
            XCTAssertNil(result.orientationAdjustment); XCTAssertNil(result.adjustedValue)
        }
    }
    func testRMR89WorkedOrientationExamplesAndApplicability() throws {
        var input = Self.referenceInput()
        input.orientationDescription = "Strike perpendicular to drive, 60° against dip (Table 4.2)"
        input.orientationFavorability = .fair
        XCTAssertNil(try input.basicEvaluation().adjustedValue) // No application.
        input.application = .tunnelsAndMines
        let tunnel = try input.basicEvaluation()
        XCTAssertEqual(tunnel.value, 64); XCTAssertEqual(tunnel.orientationAdjustment, -5)
        XCTAssertEqual(tunnel.adjustedValue, 59); XCTAssertEqual(tunnel.adjustedRockClass, "III — среднее качество")
        input.orientationDescription = " \n"
        XCTAssertNil(try input.basicEvaluation().orientationAdjustment)

        for (application, expected) in [(RMREngineeringApplication.tunnelsAndMines, [0, -2, -5, -10, -12]),
                                        (.foundations, [0, -2, -7, -15, -25]), (.slopes, [0, -5, -25, -50, -60])] {
            input.application = application
            input.orientationDescription = "Documented application-specific engineering interpretation"
            for (category, adjustment) in zip(RMR89OrientationFavorability.allCases, expected) {
                input.orientationFavorability = category
                let result = try input.basicEvaluation()
                XCTAssertEqual(result.orientationAdjustment, adjustment)
                XCTAssertEqual(result.adjustedValue, 64 + adjustment)
            }
        }
        input.basicSelections?["rqd"] = nil
        let partial = try input.basicEvaluation()
        XCTAssertEqual(partial.orientationAdjustment, -60); XCTAssertNil(partial.adjustedValue)
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
    func testRMR89StrengthRQDAndSpacingBoundaries() throws {
        var input = Self.referenceInput()
        input.strengthTest = .ucs
        for (number, category, score) in [("250.0001", 0, 15), ("250", 1, 12), ("100", 1, 12), ("100", 2, 7),
                                           ("50", 3, 4), ("25", 4, 2), ("5", 5, 1), ("1", 5, 1), ("0.9999", 6, 0)] {
            input.strengthMPa = number; input.basicSelections?["strength"] = "strength-\(category)"
            XCTAssertEqual(try input.basicEvaluation().components["strength"], score)
        }
        input.strengthMPa = "1"; XCTAssertThrowsError(try input.basicEvaluation())
        input.strengthTest = .pointLoadIs50; input.strengthMPa = "0.9"; input.basicSelections?["strength"] = nil
        XCTAssertTrue(try input.basicEvaluation().missing.contains { $0.contains("требуется UCS") })
        input = Self.referenceInput()
        for (number, category, score) in [("100", 0, 20), ("90", 0, 20), ("90", 1, 17), ("75", 2, 13), ("50", 3, 8), ("25", 3, 8), ("0", 4, 3)] {
            input.rqd = number; input.basicSelections?["rqd"] = "rqd-\(category)"
            XCTAssertEqual(try input.basicEvaluation().components["rqd"], score)
        }
        input.rqd = "25"; XCTAssertThrowsError(try input.basicEvaluation())
        input.rqd = "0"
        for (number, category, score) in [("2.0001", 0, 20), ("2", 1, 15), ("0.6", 1, 15), ("0.6", 2, 10),
                                           ("0.2", 3, 8), ("0.06", 3, 8), ("0.0599", 4, 5)] {
            input.spacingMeters = number; input.basicSelections?["spacing"] = "spacing-\(category)"
            XCTAssertEqual(try input.basicEvaluation().components["spacing"], score)
        }
        input.spacingMeters = "0.06"; XCTAssertThrowsError(try input.basicEvaluation())
    }

    func testRMR89GroundwaterAlternativesAndConflicts() throws {
        var input = Self.referenceInput()
        for (inflow, ratio, category, score) in [("0", "0", 0, 15), ("9.99", "0.099", 1, 10), ("10", "0.1", 2, 7),
                                                ("25", "0.2", 2, 7), ("25", "0.2", 3, 4), ("125", "0.5", 3, 4), ("125.01", "0.501", 4, 0)] {
            input.inflowLitersPerMinutePer10m = inflow; input.waterPressureRatio = ratio
            input.basicSelections?["groundwater"] = "groundwater-\(category)"
            let result = try input.basicEvaluation()
            XCTAssertEqual(result.components["groundwater"], score); XCTAssertEqual(result.value, 57 + score)
        }
        input.basicSelections?["groundwater"] = "groundwater-0"
        XCTAssertThrowsError(try input.basicEvaluation())
        XCTAssertEqual(try input.historicalBasicEvaluation().value, 72)
        input.basicSelections?["groundwater"] = nil
        XCTAssertNil(try input.basicEvaluation().value) // Numeric evidence cannot silently select the row.
        input.inflowLitersPerMinutePer10m = "0"; XCTAssertThrowsError(try input.basicEvaluation())
    }
    func testFilledDiscontinuitiesRequireExplicitA4InsteadOfEAddition() throws {
        var input = Self.referenceInput(); input.basicSelections?["infill"] = "infill-4"
        XCTAssertNil(try input.basicEvaluation().value)
        input.basicSelections?["overallCondition"] = "overallCondition-4"
        input.overallConditionContinuity = .continuous
        XCTAssertEqual(try input.basicEvaluation().value, 42)
        XCTAssertEqual(try input.basicEvaluation().components["condition"], 0)
        input.basicSelections?["roughness"] = "roughness-0"
        XCTAssertEqual(try input.basicEvaluation().value, 42) // Gouge masks roughness.
        input.basicSelections?["overallCondition"] = "overallCondition-0"
        XCTAssertThrowsError(try input.basicEvaluation())
        input.basicSelections?["overallCondition"] = nil
        input.basicSelections?["infill"] = "infill-2"
        XCTAssertNil(try input.basicEvaluation().value) // Hard >5 mm is not uniquely covered by A.4.
    }
    private func directA4Input(_ row: Int) -> RMR89Input {
        var input = Self.referenceInput()
        for key in ["persistence", "aperture", "roughness", "infill", "weathering"] { input.basicSelections?[key] = nil }
        input.apertureMillimeters = ""; input.persistenceMeters = ""
        input.basicSelections?["overallCondition"] = "overallCondition-\(row)"
        return input
    }

    func testRMR89A4RowSelectionAloneCannotSupplyEvidence() throws {
        for (row, missingCount) in [4, 3, 3, 2, 2].enumerated() {
            let result = try directA4Input(row).basicEvaluation()
            XCTAssertNil(result.components["condition"]); XCTAssertNil(result.value)
            XCTAssertEqual(result.missing.count, missingCount, "A.4 row \(row)")
            XCTAssertTrue(result.missing.allSatisfy { $0.hasPrefix("A.4:") })
        }
    }

    func testRMR89A4ThirtyRequiresAllFourDescriptors() throws {
        var input = directA4Input(0)
        input.basicSelections?["roughness"] = "roughness-0"; input.basicSelections?["weathering"] = "weathering-0"
        input.apertureMillimeters = "0"; input.persistenceMeters = "0.5"
        let unconfirmed = try input.basicEvaluation()
        XCTAssertNil(unconfirmed.value); XCTAssertEqual(unconfirmed.missing, ["A.4: требуется подтверждение (прерывистость)"])
        input.overallConditionContinuity = .continuous
        XCTAssertThrowsError(try input.basicEvaluation())
        input.overallConditionContinuity = .discontinuous
        XCTAssertEqual(try input.basicEvaluation().value, 72)
        for (key, wrong) in [("roughness", "roughness-1"), ("weathering", "weathering-1")] {
            var changed = input; changed.basicSelections?[key] = nil
            XCTAssertNil(try changed.basicEvaluation().value)
            changed.basicSelections?[key] = wrong
            XCTAssertThrowsError(try changed.basicEvaluation())
        }
        input.apertureMillimeters = ""; XCTAssertNil(try input.basicEvaluation().value)
        input.basicSelections?["aperture"] = "aperture-0"; XCTAssertEqual(try input.basicEvaluation().value, 72)
        input.basicSelections?["aperture"] = nil; input.apertureMillimeters = "0.0001"
        XCTAssertThrowsError(try input.basicEvaluation())
    }

    func testRMR89A4ThirtyRejectsSelectedGougeWithClosedWalls() throws {
        var input = directA4Input(0)
        input.overallConditionContinuity = .discontinuous
        input.basicSelections?["roughness"] = "roughness-0"; input.basicSelections?["weathering"] = "weathering-0"
        input.apertureMillimeters = "0"
        XCTAssertEqual(try input.basicEvaluation().value, 72)
        input.basicSelections?["infill"] = "infill-0"
        XCTAssertEqual(try input.basicEvaluation().value, 72)
        for category in ["infill-1", "infill-2", "infill-3", "infill-4"] {
            input.basicSelections?["infill"] = category
            XCTAssertThrowsError(try input.basicEvaluation(), category) { error in
                XCTAssertTrue(error.localizedDescription.contains("заполнитель"))
            }
        }
    }

    func testRMR89A4TwentyFiveAndTwentyRequireMatchingWallsRoughnessAndAperture() throws {
        for (row, weathering, wrong, total) in [(1, "weathering-1", "weathering-3", 67), (2, "weathering-3", "weathering-1", 62)] {
            var input = directA4Input(row)
            input.basicSelections?["roughness"] = "roughness-2"; input.basicSelections?["weathering"] = weathering
            input.basicSelections?["aperture"] = "aperture-2" // Includes 1 mm, so cannot establish <1 mm.
            XCTAssertNil(try input.basicEvaluation().value)
            input.apertureMillimeters = "0.5"
            XCTAssertEqual(try input.basicEvaluation().value, total) // Continuity is absent from both printed rows.
            input.apertureMillimeters = "1"; XCTAssertThrowsError(try input.basicEvaluation())
            input.apertureMillimeters = "0.5"; input.basicSelections?["weathering"] = nil
            XCTAssertNil(try input.basicEvaluation().value)
            input.basicSelections?["weathering"] = wrong; XCTAssertThrowsError(try input.basicEvaluation())
            input.basicSelections?["weathering"] = weathering; input.basicSelections?["roughness"] = "roughness-3"
            XCTAssertThrowsError(try input.basicEvaluation())
        }
    }

    func testRMR89A4NarrowRowsRejectThickGougeWithoutBanningThinGouge() throws {
        for (row, weathering, total) in [(1, "weathering-1", 67), (2, "weathering-3", 62)] {
            var input = directA4Input(row)
            input.basicSelections?["roughness"] = "roughness-2"; input.basicSelections?["weathering"] = weathering
            input.apertureMillimeters = "0.5"
            XCTAssertEqual(try input.basicEvaluation().value, total)
            for category in ["infill-0", "infill-1", "infill-3"] {
                input.basicSelections?["infill"] = category
                XCTAssertEqual(try input.basicEvaluation().value, total, category)
            }
            input.apertureMillimeters = "0"
            XCTAssertThrowsError(try input.basicEvaluation()) // Selected thin gouge still has positive thickness.
            input.apertureMillimeters = "0.5"
            for category in ["infill-2", "infill-4"] {
                input.basicSelections?["infill"] = category
                XCTAssertThrowsError(try input.basicEvaluation(), category)
            }
            let date = Date(timeIntervalSince1970: 100)
            let old = try RMR89Assessment(input: input, now: date, method: RMR89Assessment.preA4VerificationVersion)
            let decoded = try JSONDecoder().decode(RMR89Assessment.self, from: JSONEncoder().encode(old))
            try decoded.validate()
            XCTAssertEqual(decoded, old); XCTAssertEqual(decoded.calculation?.value, total)
        }
    }

    func testRMR89A4TenRequiresContinuityAndOneOfThreeAlternatives() throws {
        var input = directA4Input(3)
        input.persistenceMeters = "25"; input.apertureMillimeters = "2"
        XCTAssertNil(try input.basicEvaluation().value)
        input.overallConditionContinuity = .discontinuous
        XCTAssertThrowsError(try input.basicEvaluation())
        input.overallConditionContinuity = .continuous
        input.apertureMillimeters = ""; XCTAssertNil(try input.basicEvaluation().value)
        for (key, category) in [("roughness", "roughness-4"), ("infill", "infill-1"), ("infill", "infill-3")] {
            var confirmed = input; confirmed.basicSelections?[key] = category
            XCTAssertEqual(try confirmed.basicEvaluation().value, 52)
        }
        input.basicSelections?["roughness"] = "roughness-3"; input.basicSelections?["infill"] = "infill-2"
        for aperture in ["1", "5"] {
            input.apertureMillimeters = aperture; XCTAssertEqual(try input.basicEvaluation().value, 52)
        }
        for aperture in ["0.999", "5.001"] {
            input.apertureMillimeters = aperture; XCTAssertThrowsError(try input.basicEvaluation())
        }
        input.basicSelections?["roughness"] = "roughness-4"
        XCTAssertEqual(try input.basicEvaluation().value, 52) // A.4 independently accepts observed slickensides.
        input.basicSelections?["infill"] = "infill-4"
        XCTAssertEqual(try input.basicEvaluation().value, 52) // The table gives no precedence between supported rows.
        input.basicSelections?["roughness"] = "roughness-3"
        XCTAssertThrowsError(try input.basicEvaluation()) // Thick soft gouge cannot satisfy the <5 mm alternative.
    }

    func testRMR89A4ZeroRequiresContinuityAndOneOfTwoAlternatives() throws {
        var input = directA4Input(4)
        input.apertureMillimeters = "8"; input.basicSelections?["infill"] = "infill-2"
        XCTAssertNil(try input.basicEvaluation().value)
        input.overallConditionContinuity = .discontinuous; XCTAssertThrowsError(try input.basicEvaluation())
        input.overallConditionContinuity = .continuous
        let wide = try input.basicEvaluation()
        XCTAssertEqual(wide.components["condition"], 0); XCTAssertEqual(wide.value, 42)
        input.apertureMillimeters = "5"; XCTAssertThrowsError(try input.basicEvaluation())
        input.basicSelections?["infill"] = "infill-3"; XCTAssertThrowsError(try input.basicEvaluation())
        input.apertureMillimeters = "5.001"; XCTAssertEqual(try input.basicEvaluation().value, 42)
        input.apertureMillimeters = "5"
        input.basicSelections?["infill"] = nil; XCTAssertNil(try input.basicEvaluation().value)
        input.apertureMillimeters = ""; input.basicSelections?["infill"] = "infill-4"
        XCTAssertEqual(try input.basicEvaluation().value, 42)
    }

    func testRMR89ChartEBoundaries() throws {
        var input = Self.referenceInput()
        input.persistenceMeters = "3"; input.apertureMillimeters = "1"
        XCTAssertEqual(try input.basicEvaluation().components["condition"], 22)
        input.basicSelections?["persistence"] = "persistence-2"; input.basicSelections?["aperture"] = "aperture-3"
        XCTAssertEqual(try input.basicEvaluation().components["condition"], 17)
        input.persistenceMeters = "20"; input.basicSelections?["persistence"] = "persistence-4"
        XCTAssertThrowsError(try input.basicEvaluation())
    }

    func testRMR89LowUCSZeroComponentsAndOutOfScaleSum() throws {
        var input = RMR89Input(); input.strengthTest = .ucs; input.strengthMPa = "0.5"
        input.rqd = "0"; input.spacingMeters = "0.03"; input.apertureMillimeters = "8"
        input.inflowLitersPerMinutePer10m = "200"
        input.basicSelections = ["strength": "strength-6", "rqd": "rqd-4", "spacing": "spacing-4", "overallCondition": "overallCondition-4", "groundwater": "groundwater-4"]
        input.overallConditionContinuity = .continuous
        input.application = .tunnelsAndMines; input.orientationFavorability = .unfavorable
        input.orientationDescription = "Continuous set, strike perpendicular, 30° against drive"
        let result = try input.basicEvaluation()
        XCTAssertEqual(result.components, ["strength": 0, "rqd": 3, "spacing": 5, "condition": 0, "groundwater": 0])
        XCTAssertEqual(result.value, 8); XCTAssertEqual(result.orientationAdjustment, -10)
        XCTAssertEqual(result.adjustedValue, -2); XCTAssertNil(result.adjustedRockClass)
    }
    func testCalculatedSnapshotRoundTripRejectsTamperingAndKeepsLegacyJSON() throws {
        let assessment = try RMR89Assessment(input: Self.referenceInput(), now: Date(timeIntervalSince1970: 100))
        let data = try JSONEncoder().encode(assessment)
        let reopened = try JSONDecoder().decode(RMR89Assessment.self, from: data)
        try reopened.validate(); XCTAssertEqual(reopened, assessment)
        XCTAssertEqual(reopened.method, RMR89Assessment.verifiedVersion)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var calculation = json["calculation"] as! [String: Any]; calculation["value"] = 65; json["calculation"] = calculation
        XCTAssertThrowsError(try JSONDecoder().decode(RMR89Assessment.self, from: JSONSerialization.data(withJSONObject: json)).validate())
        let legacy = #"{"method":"Bieniawski-RMR89/input-only-v1","revision":1,"assessedAt":0,"input":{"strengthMPa":"","strengthEvidence":"Исходный журнал","rqd":"","rqdEvidence":"","spacingMeters":"","persistenceMeters":"","apertureMillimeters":"","roughness":"","infill":"","weathering":"","groundwater":"","inflowLitersPerMinutePer10m":"","waterPressureRatio":"","orientationDescription":"","source":"Архив","assessor":"","missingReason":""},"missing":["Прочность","RQD","Расстояние","Протяжённость","Раскрытие","Шероховатость","Заполнитель","Выветрелость","Ориентация","Подземные воды","Метод испытания прочности","Инженерное применение"]}"#
        let old = try JSONDecoder().decode(RMR89Assessment.self, from: Data(legacy.utf8))
        try old.validate(); XCTAssertNil(old.calculation); XCTAssertNil(old.input.basicSelections)
        XCTAssertEqual(old.input.strengthEvidence, "Исходный журнал")
    }

    func testRMR89HistoricalCalculatedMethodsValidateAgainstTheirOwnSnapshots() throws {
        let now = Date(timeIntervalSince1970: 100)
        var input = Self.referenceInput(); input.basicSelections?["groundwater"] = "groundwater-0"
        input.inflowLitersPerMinutePer10m = "200"
        let old = try RMR89Assessment(input: input, now: now, method: RMR89Assessment.calculatedVersion)
        XCTAssertEqual(old.calculation?.value, 72); XCTAssertNil(old.calculation?.adjustedValue)
        let reopened = try JSONDecoder().decode(RMR89Assessment.self, from: JSONEncoder().encode(old))
        try reopened.validate(); XCTAssertEqual(reopened, old)
        XCTAssertThrowsError(try RMR89Assessment(input: input, now: now))

        input = Self.referenceInput(); input.strengthTest = .fieldEstimate; input.strengthMPa = ""
        input.basicSelections?["strength"] = nil; input.fieldStrength = FieldStrengthAssessment(.R0)
        let field = try RMR89Assessment(input: input, now: now, method: RMR89Assessment.fieldStrengthVersion)
        let fieldReopened = try JSONDecoder().decode(RMR89Assessment.self, from: JSONEncoder().encode(field))
        try fieldReopened.validate(); XCTAssertEqual(fieldReopened, field)
        XCTAssertEqual(field.calculation?.value, 52); XCTAssertNil(field.calculation?.orientationAdjustment)
    }

    func testRMR89V3A4SnapshotRetainsOriginalResultAndV4ProtectsConfirmation() throws {
        let now = Date(timeIntervalSince1970: 100)
        var input = directA4Input(3)
        input.apertureMillimeters = "2"
        input.application = .tunnelsAndMines; input.orientationFavorability = .fair; input.orientationDescription = "Recorded assessment"
        let v3 = try RMR89Assessment(input: input, now: now, method: RMR89Assessment.preA4VerificationVersion)
        let saved = try JSONDecoder().decode(RMR89Assessment.self, from: JSONEncoder().encode(v3))
        try saved.validate(); XCTAssertEqual(saved, v3)
        XCTAssertNil(saved.input.overallConditionContinuity)
        XCTAssertEqual(saved.calculation?.value, 52); XCTAssertEqual(saved.calculation?.adjustedValue, 47)
        XCTAssertNil(try RMR89Assessment(input: input, now: now).calculation?.value)

        input.overallConditionContinuity = .continuous
        let v4 = try RMR89Assessment(input: input, now: now)
        XCTAssertEqual(v4.method, RMR89Assessment.verifiedVersion); XCTAssertEqual(v4.calculation?.adjustedValue, 47)
        let bytes = try JSONEncoder().encode(v4)
        let reopened = try JSONDecoder().decode(RMR89Assessment.self, from: bytes)
        try reopened.validate(); XCTAssertEqual(reopened.input.overallConditionContinuity, .continuous)
        var snapshot = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        var alteredInput = try XCTUnwrap(snapshot["input"] as? [String: Any])
        alteredInput["overallConditionContinuity"] = nil; snapshot["input"] = alteredInput
        let tampered = try JSONDecoder().decode(RMR89Assessment.self, from: JSONSerialization.data(withJSONObject: snapshot))
        XCTAssertThrowsError(try tampered.validate())
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
        correction.fields.rmr89.application = .tunnelsAndMines
        correction.fields.rmr89.orientationFavorability = .fair
        correction.fields.rmr89.orientationDescription = "Strike perpendicular, 60° against drive"
        _ = try workflow.saveCorrection(correction)
        let before = workflow.journal
        let selection = MappingCSVExportTests().selection(original, "2023-11-14T12:00:00Z")
        let snapshot = try MappingCSVExport.prepare(journal: before, selection: selection)
        XCTAssertEqual(snapshot.fieldTables.map(\.name), ["Наблюдения", "Системы трещин", "Тектоника", "Рейтинги массива", "Фотографии", "field_links"])
        for table in snapshot.fieldTables { XCTAssertTrue(table.rows.allSatisfy { $0.count == table.columns.count }, table.name) }
        let field = snapshot.fieldTables[0], row = try XCTUnwrap(field.rows.first)
        if case .number(let value) = row[field.columns.firstIndex(of: "X")!] { XCTAssertEqual(value, 123456.12345678912) } else { XCTFail("Numeric X") }
        if case .integer(let value) = row[field.columns.firstIndex(of: "RMR89 базовый")!] { XCTAssertEqual(value, 64) } else { XCTFail("Numeric RMR") }
        let ratings = try XCTUnwrap(snapshot.fieldTables.first { $0.name == "Рейтинги массива" })
        let rmrRow = try XCTUnwrap(ratings.rows.last)
        guard case .integer(-5) = rmrRow[try XCTUnwrap(ratings.columns.firstIndex(of: "Поправка на ориентацию"))],
              case .integer(59) = rmrRow[try XCTUnwrap(ratings.columns.firstIndex(of: "RMR с ориентацией"))] else {
            return XCTFail("Numeric orientation correction and adjusted RMR")
        }
        let technical = try XCTUnwrap(snapshot.tables.first { $0.name == "assessments" })
        let stored = try XCTUnwrap(technical.rows.last?[try XCTUnwrap(technical.columns.firstIndex(of: "stored_rmr_calculation_json"))])
        if case .text(let json) = stored {
            let evaluation = try JSONDecoder().decode(RMR89BasicEvaluation.self, from: Data(json.utf8))
            XCTAssertEqual(evaluation.value, 64); XCTAssertEqual(evaluation.orientationAdjustment, -5); XCTAssertEqual(evaluation.adjustedValue, 59)
        } else { XCTFail("Stored RMR89 evaluation JSON") }
        let files = try MappingExportFiles.write(snapshot); defer { files.cleanup() }
        XCTAssertEqual(files.urls.count, 1); XCTAssertEqual(files.urls[0].pathExtension, "xlsx")
        XCTAssertEqual(workflow.journal, before)
        XCTAssertEqual(EngineeringDisplay.coordinate(123456.12345678912), "123456,1")
    }
    func testRepresentativeWorkbookFixtureWhenRequested() throws {
        guard let path = ProcessInfo.processInfo.environment["FF_FINAL_EXPORT_FIXTURE_DIR"] else { throw XCTSkip("Opt-in independent workbook fixture") }
        let (_, initial, original) = try P33RevisionTests().seed(includeHistoricalJ5: true); var workflow = initial
        try workflow.updateProject(id: original.projectID, name: "Рудник Северный")
        try workflow.updateExcavation(id: original.excavationID, name: "Штрек Восточный № 3", horizonIDs: [original.horizonID])
        var correction = try workflow.correction(for: original.id)
        correction.fields.x = "123456.12345678912"; correction.fields.y = "-0.123456789123456"
        correction.fields.rmr89 = Self.referenceInput(); correction.reason = "Полевой журнал"
        correction.fields.notes = "Кварцевая жила; угол 45°; μ/µ; раскрытие ≤1 мм.\n=1+1 — буквальная заметка"
        for id in [JointSetIdentifier.J3, .J4] {
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
