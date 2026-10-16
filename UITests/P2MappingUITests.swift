import XCTest

final class P2MappingUITests: XCTestCase {
    @MainActor func testTwoPlansPickingSavedMarkersOverlapAndDraftRetention() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FIELD_FORGE_TEST_RUN_ID"] = UUID().uuidString
        app.launchArguments = ["--ui-testing"]
        // Simulator-only import input; normal setup, managed-file import and commit run unchanged.
        // The system Files picker is exercised separately below, without publishing Documents.
        app.launchEnvironment["P2_PLAN_A"] = dxf("0\nLINE\n10\n100\n20\n200\n11\n300\n21\n400\n")
        app.launchEnvironment["P2_PLAN_B"] = dxf("0\nCIRCLE\n10\n100\n20\n200\n40\n20\n"
            + "0\nPOINT\n10\n100\n20\n200\n30\n500\n"
            + "0\nTEXT\n10\n105\n20\n205\n40\n2\n50\n30\n1\nПК 0+100\n"
            + "0\nMTEXT\n10\n90\n20\n190\n40\n3\n1\nПервая\\PВторая\n")
        app.launch()
        let project = "P2-\(UUID().uuidString.prefix(8))"
        create("projectPicker", value: project, app: app); select("projectPicker", value: project, app: app)
        create("horizonPicker", value: "+393", app: app); select("horizonPicker", value: "+393 м", app: app)
        create("excavationPicker", value: "P2 штрек", app: app); select("excavationPicker", value: "P2 штрек", app: app)
        XCTAssertFalse(app.textFields["mappingCRS"].exists); XCTAssertFalse(app.textFields["mappingAxes"].exists)
        XCTAssertFalse(app.textFields["mappingProvenance"].exists)
        XCTAssertFalse(app.staticTexts["Начало и направление отсчёта"].exists)
        enter("mappingPicket", value: "ПК 0+005", app: app)
        reveal(app.textFields["mappingZ"], app: app)
        XCTAssertEqual(app.textFields["mappingZ"].value as? String, "393")
        enter("mappingZ", value: "390.5", app: app, replacing: true)
        openPlans(app)
        importFixture("P2_PLAN_A", version: "A", app: app)
        importFixture("P2_PLAN_B", version: "B", app: app)
        XCTAssertTrue(app.staticTexts["P2_PLAN_A.dxf"].exists)
        XCTAssertTrue(app.staticTexts["P2_PLAN_B.dxf"].exists)
        // Real system file chooser smoke check. Fixture import above does not bypass parser/storage.
        app.buttons["importDXF"].tap()
        let cancel = app.buttons.matching(NSPredicate(format: "label IN %@", ["Cancel", "Отменить", "Отмена"])).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 10)); cancel.tap()
        app.staticTexts["P2_PLAN_A.dxf"].tap()
        let canvas = app.otherElements["planCanvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        app.buttons["planZoomIn"].tap()
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.1,
            thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.6)))
        // The drawing centre is now at viewport centre + the drag's 10% translation.
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.6)).tap()
        XCTAssertTrue(app.buttons["confirmPlanXY"].waitForExistence(timeout: 5))
        screenshot("P2 proposed plan point", app: app)
        app.buttons["confirmPlanXY"].tap()
        XCTAssertTrue(app.buttons["selectHorizonPlan"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["mappingZ"].value as? String, "390.5")
        XCTAssertEqual(Double(app.textFields["mappingX"].value as? String ?? "" ) ?? .nan, 200, accuracy: 0.5)
        XCTAssertEqual(Double(app.textFields["mappingY"].value as? String ?? "" ) ?? .nan, 300, accuracy: 0.5)
        reveal(app.textFields["mappingPicket"], app: app, down: true)
        XCTAssertEqual(app.textFields["mappingPicket"].value as? String, "ПК 0+005")
        save(app)
        reveal(app.textFields["mappingZ"], app: app, down: true)
        XCTAssertEqual(app.textFields["mappingZ"].value as? String, "393")
        reveal(app.textFields["mappingPicket"], app: app, down: true)
        enter("mappingPicket", value: "ПК 0+010", app: app)
        openPlans(app); app.staticTexts["P2_PLAN_A.dxf"].tap()
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        // Tap actual marker at the same drawing position, then open its original journal record.
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["ПК 0+005"].waitForExistence(timeout: 5))
        app.staticTexts["ПК 0+005"].tap()
        XCTAssertTrue(app.staticTexts["Исходное наблюдение · только просмотр"].waitForExistence(timeout: 5))
        screenshot("P2 saved point detail", app: app)
        app.buttons["Закрыть"].tap()
        XCTAssertTrue(app.buttons["planPoints"].waitForExistence(timeout: 5))
        // Different revision has no overlays even with identical project/horizon.
        app.navigationBars["P2_PLAN_A.dxf"].buttons.element(boundBy: 0).tap()
        app.staticTexts["P2_PLAN_B.dxf"].tap()
        XCTAssertTrue(app.buttons["planPoints"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["planPoints"].label.contains("0"))
        XCTAssertTrue((canvas.value as? String ?? "").contains("POINT: 1; подписи: 2"))
        screenshot("P2 POINT TEXT MTEXT display", app: app)
        app.navigationBars["P2_PLAN_B.dxf"].buttons.element(boundBy: 0).tap()
        app.staticTexts["P2_PLAN_A.dxf"].tap()
        // Propose on empty space, then deliberately enter overlapping XY in that drawing frame.
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.5)).tap()
        app.buttons["confirmPlanXY"].tap()
        reveal(app.textFields["mappingX"], app: app, down: true)
        enter("mappingX", value: "200", app: app, replacing: true)
        enter("mappingY", value: "300", app: app, replacing: true)
        reveal(app.textFields["mappingPicket"], app: app, down: true)
        XCTAssertEqual(app.textFields["mappingPicket"].value as? String, "ПК 0+010")
        save(app)
        openPlans(app); app.staticTexts["P2_PLAN_A.dxf"].tap()
        XCTAssertTrue(app.buttons["planPoints"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["planPoints"].label.contains("2")); canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["ПК 0+005"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["ПК 0+010"].exists)
        screenshot("P2 plan point list", app: app)
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["projectPicker"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["projectPicker"].label.contains(project))
        openPlans(app)
        XCTAssertTrue(app.staticTexts["P2_PLAN_A.dxf"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["P2_PLAN_B.dxf"].exists)
    }
    @MainActor func testOriginalHorizon200ImportProjectionPickingAndMarker() throws {
        try verifyOriginal(level: 200, centerX: 4828.989245694731, centerY: 10204.5, polylines: 13, vertices: 627)
    }
    @MainActor func testOriginalHorizon300ImportProjectionPickingAndMarker() throws {
        try verifyOriginal(level: 300, centerX: 4828.999038089427, centerY: 10064.5, polylines: 13, vertices: 627)
    }
    @MainActor func testOriginalHorizon400ImportProjectionPickingAndMarker() throws {
        try verifyOriginal(level: 400, centerX: 4918.987672812805, centerY: 9960, polylines: 4, vertices: 294)
    }
    @MainActor private func verifyOriginal(level: Int, centerX: Double, centerY: Double, polylines: Int, vertices: Int) throws {
        let root = try XCTUnwrap(Bundle(for: P2MappingUITests.self).url(forResource: "Fixtures", withExtension: nil))
        let data = try Data(contentsOf: root.appendingPathComponent("DXFReal/horizon_\(level)_3d.dxf"))
        let app = XCUIApplication()
        app.launchEnvironment["FIELD_FORGE_TEST_RUN_ID"] = UUID().uuidString
        app.launchArguments = ["--ui-testing"]
        app.launchEnvironment["P2_PLAN_A"] = try XCTUnwrap(String(data: data, encoding: .utf8))
        app.launch()
        let project = "Original-\(level)-\(UUID().uuidString.prefix(6))"
        create("projectPicker", value: project, app: app); select("projectPicker", value: project, app: app)
        create("horizonPicker", value: "\(level)", app: app); select("horizonPicker", value: "+\(level) м", app: app)
        create("excavationPicker", value: "Штрек \(level)", app: app); select("excavationPicker", value: "Штрек \(level)", app: app)
        enter("mappingPicket", value: "ПК 0+005", app: app)
        reveal(app.textFields["mappingZ"], app: app)
        XCTAssertEqual(app.textFields["mappingZ"].value as? String, "\(level)")
        enter("mappingZ", value: "-12.125", app: app, replacing: true)
        openPlans(app); importFixture("P2_PLAN_A", version: "original-\(level)", app: app)
        app.staticTexts["P2_PLAN_A.dxf"].tap()
        let canvas = app.otherElements["planCanvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        XCTAssertTrue((canvas.value as? String ?? "").contains("Полилинии: \(polylines); вершины: \(vertices)"))
        screenshot("Original \(level) fitted XY projection", app: app)
        app.buttons["planZoomIn"].tap()
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.1,
            thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.6)))
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.6)).tap()
        XCTAssertTrue(app.buttons["confirmPlanXY"].waitForExistence(timeout: 5))
        screenshot("Original \(level) XY projection proposed", app: app)
        app.buttons["confirmPlanXY"].tap()
        XCTAssertTrue(app.buttons["selectHorizonPlan"].waitForExistence(timeout: 5))
        XCTAssertEqual(Double(app.textFields["mappingX"].value as? String ?? "") ?? .nan, centerX, accuracy: 2)
        XCTAssertEqual(Double(app.textFields["mappingY"].value as? String ?? "") ?? .nan, centerY, accuracy: 2)
        XCTAssertEqual(app.textFields["mappingZ"].value as? String, "-12.125")
        reveal(app.textFields["mappingPicket"], app: app, down: true)
        XCTAssertEqual(app.textFields["mappingPicket"].value as? String, "ПК 0+005")
        save(app)
        reveal(app.textFields["mappingZ"], app: app, down: true)
        XCTAssertEqual(app.textFields["mappingZ"].value as? String, "\(level)")
        openPlans(app); app.staticTexts["P2_PLAN_A.dxf"].tap()
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        XCTAssertTrue((canvas.value as? String ?? "").contains("маркеры в окне: 1"))
        screenshot("Original \(level) saved blue marker", app: app)
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["ПК 0+005"].waitForExistence(timeout: 5))
        app.staticTexts["ПК 0+005"].tap()
        XCTAssertTrue(app.staticTexts["Исходное наблюдение · только просмотр"].waitForExistence(timeout: 5))
        app.buttons["Закрыть"].tap()
        app.terminate(); app.launch()
        openPlans(app)
        XCTAssertTrue(app.staticTexts["P2_PLAN_A.dxf"].waitForExistence(timeout: 5))
        // Journal filters are separate from sorting, searchable and resettable.
        app.buttons["Вернуться"].tap()
        app.buttons["mappingJournal"].tap()
        XCTAssertTrue(app.buttons["journalHorizonFilter"].waitForExistence(timeout: 5))
        app.buttons["journalHorizonFilter"].tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5))
        app.searchFields.firstMatch.tap(); app.searchFields.firstMatch.typeText("\(level)")
        app.buttons["+\(level) м"].tap()
        app.buttons["journalExcavationFilter"].tap()
        app.searchFields.firstMatch.tap(); app.searchFields.firstMatch.typeText("\(level)")
        app.buttons["Штрек \(level)"].tap()
        app.searchFields.firstMatch.tap(); app.searchFields.firstMatch.typeText("no-match")
        XCTAssertTrue(app.staticTexts["journalEmpty"].waitForExistence(timeout: 5))
        let cancel = app.buttons.matching(NSPredicate(format: "label IN %@", ["Cancel", "Отмена", "Отменить"])).firstMatch
        if cancel.exists { cancel.tap() }
        app.buttons["journalClearFilters"].tap()
        XCTAssertTrue(app.staticTexts["ПК 0+005"].waitForExistence(timeout: 5))
    }
    private func dxf(_ entities: String) -> String {
        "0\nSECTION\n2\nHEADER\n9\n$INSUNITS\n70\n6\n0\nENDSEC\n0\nSECTION\n2\nENTITIES\n\(entities)0\nENDSEC\n0\nEOF\n"
    }
    @MainActor private func importFixture(_ key: String, version: String, app: XCUIApplication) {
        app.buttons[key].tap()
        XCTAssertTrue(app.textFields["planVersion"].waitForExistence(timeout: 5))
        enter("planVersion", value: version, app: app, replacing: true)
        let save = app.buttons["savePlanImport"]; reveal(save, app: app); save.tap()
        XCTAssertTrue(app.buttons["importDXF"].waitForExistence(timeout: 5))
    }
    @MainActor private func create(_ picker: String, value: String, app: XCUIApplication) {
        let button = app.buttons["manage-\(picker)"]; XCTAssertTrue(button.waitForExistence(timeout: 10)); button.tap()
        let id = picker == "horizonPicker" ? "contextElevation" : "contextName"
        XCTAssertTrue(app.textFields[id].waitForExistence(timeout: 5)); enter(id, value: value, app: app)
        app.buttons["saveContext"].tap(); XCTAssertTrue(button.waitForExistence(timeout: 5))
    }
    @MainActor private func select(_ picker: String, value: String, app: XCUIApplication) { app.buttons[picker].tap(); app.buttons[value].tap() }
    @MainActor private func enter(_ id: String, value: String, app: XCUIApplication, replacing: Bool = false) {
        let field = app.textFields[id]; field.tap()
        if replacing, let old = field.value as? String { field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count)) }
        field.typeText(value)
        if app.buttons["Готово"].exists { app.buttons["Готово"].tap() }
    }
    @MainActor private func reveal(_ element: XCUIElement, app: XCUIApplication, down: Bool = false) {
        for _ in 0..<15 {
            if element.isHittable { return }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: down ? 0.55 : 0.78))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: down ? 0.78 : 0.55))
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        XCTAssertTrue(element.isHittable)
    }
    @MainActor private func openPlans(_ app: XCUIApplication) {
        let button = app.buttons["selectHorizonPlan"]
        if !button.isHittable { reveal(app.textFields["mappingPicket"], app: app, down: true); reveal(button, app: app) }
        button.tap(); XCTAssertTrue(app.buttons["importDXF"].waitForExistence(timeout: 5))
    }
    @MainActor private func save(_ app: XCUIApplication) {
        let button = app.buttons["saveMappingObservation"]
        for _ in 0..<16 { if button.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(button.isHittable); button.tap()
        XCTAssertTrue(app.alerts["Наблюдение сохранено"].waitForExistence(timeout: 5)); app.buttons["Продолжить"].tap()
    }
    @MainActor private func screenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
