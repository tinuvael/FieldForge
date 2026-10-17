import XCTest

final class MappingUITests: XCTestCase {
    @MainActor func testSuccessiveObservationsContextGuardJournalAndRelaunch() throws {
        let app = XCUIApplication(); app.launchEnvironment["FIELD_FORGE_TEST_RUN_ID"] = UUID().uuidString; app.launchArguments = ["--ui-testing"]; app.launch()
        let suffix = String(UUID().uuidString.prefix(8))
        let project = "Рудник-\(suffix)", horizon = "+393 м", excavation = "Штрек-\(suffix)"
        create("projectPicker", name: project, app: app)
        select("projectPicker", value: project, app: app)
        create("horizonPicker", name: horizon, app: app)
        select("horizonPicker", value: horizon, app: app)
        create("excavationPicker", name: excavation, app: app)
        select("excavationPicker", value: excavation, app: app)
        let capture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        capture.name = "Mapping capture"; capture.lifetime = .keepAlways; add(capture)
        let picket = app.textFields["mappingPicket"]
        XCTAssertTrue(picket.waitForExistence(timeout: 5))
        picket.tap(); picket.typeText("1+05"); dismissKeyboard(app)
        save(app)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "неоднозначен")).firstMatch.waitForExistence(timeout: 5))
        app.buttons["Понятно"].tap()
        top(app); XCTAssertEqual(picket.value as? String, "1+05")
        picket.tap(); picket.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4)); picket.typeText("ПК 0+005")
        dismissKeyboard(app)
        // The selectors remain reachable while a draft exists; cancelling preserves it.
        app.buttons["projectPicker"].tap(); app.buttons["Не выбрано"].tap()
        XCTAssertTrue(app.buttons["Остаться"].waitForExistence(timeout: 5)); app.buttons["Остаться"].tap()
        XCTAssertEqual(picket.value as? String, "ПК 0+005")
        save(app); saved(app)
        top(app)
        XCTAssertEqual(picket.value as? String, "Пикет: ПК 0+005 или метры")
        XCTAssertTrue(app.buttons["projectPicker"].label.contains(project))
        XCTAssertTrue(app.buttons["horizonPicker"].label.contains(horizon))
        XCTAssertTrue(app.buttons["excavationPicker"].label.contains(excavation))
        picket.tap(); picket.typeText("ПК 0+010"); dismissKeyboard(app)
        save(app); saved(app)
        app.buttons["mappingJournal"].tap()
        XCTAssertTrue(app.staticTexts["ПК 0+005"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["ПК 0+010"].exists)
        app.staticTexts["ПК 0+005"].tap()
        XCTAssertTrue(app.staticTexts["Исходное наблюдение · только просмотр"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Дата наблюдения"].exists)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); screenshot.name = "Mapping observation"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["projectPicker"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["projectPicker"].label.contains(project))
        XCTAssertTrue(app.buttons["excavationPicker"].label.contains(excavation))
        app.buttons["mappingJournal"].tap()
        XCTAssertTrue(app.staticTexts["ПК 0+005"].waitForExistence(timeout: 5)); XCTAssertTrue(app.staticTexts["ПК 0+010"].exists)
        app.terminate(); app.launch()
        let other = "Другой-\(suffix)"; create("projectPicker", name: other, app: app)
        picket.tap(); picket.typeText("15"); dismissKeyboard(app)
        select("projectPicker", value: other, app: app)
        XCTAssertTrue(app.buttons["Удалить черновик"].waitForExistence(timeout: 5)); app.buttons["Удалить черновик"].tap()
        XCTAssertEqual(picket.value as? String, "Пикет: ПК 0+005 или метры")
        XCTAssertTrue(app.buttons["projectPicker"].label.contains(other))
        app.buttons["mappingJournal"].tap()
        XCTAssertTrue(app.staticTexts["journalEmpty"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["ПК 0+005"].exists)
    }
    @MainActor func testP3MixedDraftCaptureDismissBackgroundPlanTabsAndAtomicSave() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["FIELD_FORGE_TEST_RUN_ID"] = UUID().uuidString
        app.launchArguments = ["--ui-testing"]; app.launch()
        let suffix = String(UUID().uuidString.prefix(8))
        let project = "P3-\(suffix)", excavation = "E-\(suffix)"
        create("projectPicker", name: project, app: app); select("projectPicker", value: project, app: app)
        create("horizonPicker", name: "+393 м", app: app); select("horizonPicker", value: "+393 м", app: app)
        create("excavationPicker", name: excavation, app: app); select("excavationPicker", value: excavation, app: app)
        app.textFields["mappingPicket"].tap(); app.textFields["mappingPicket"].typeText("ПК 0+005"); dismissKeyboard(app)
        reveal("captureMappingManual", app: app); app.buttons["captureMappingManual"].tap()
        let add = app.buttons["addMappingMeasurement"]
        XCTAssertTrue(add.waitForExistence(timeout: 5)); XCTAssertFalse(add.isEnabled)
        app.textFields["manualDip"].tap(); app.textFields["manualDip"].typeText("45,125")
        app.textFields["manualDirection"].tap(); app.textFields["manualDirection"].typeText("270"); dismissKeyboard(app)
        XCTAssertTrue(add.isEnabled); add.tap()
        XCTAssertTrue(app.staticTexts["Замеры: 1"].waitForExistence(timeout: 5))
        app.buttons["captureMappingAutomatic"].tap()
        let hold = app.buttons["mappingHold"]
        XCTAssertTrue(hold.waitForExistence(timeout: 5))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: hold)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
        hold.tap(); XCTAssertEqual(hold.label, "Повторить"); XCTAssertTrue(add.isEnabled)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "P3 held plane dial"; screenshot.lifetime = .keepAlways; self.add(screenshot)
        // A frozen complete reading remains addable after temporary backgrounding.
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertEqual(hold.label, "Повторить"); XCTAssertTrue(add.isEnabled)
        add.tap(); XCTAssertTrue(app.staticTexts["Замеры: 2"].waitForExistence(timeout: 5))
        app.buttons["captureMappingAutomatic"].tap()
        XCTAssertTrue(app.buttons["closeMappingMeasurement"].waitForExistence(timeout: 5))
        app.buttons["closeMappingMeasurement"].tap()
        XCTAssertTrue(app.staticTexts["Замеры: 2"].waitForExistence(timeout: 5))
        top(app); app.buttons["selectHorizonPlan"].tap()
        XCTAssertTrue(app.buttons["Вернуться"].waitForExistence(timeout: 5)); app.buttons["Вернуться"].tap()
        app.tabBars.buttons["План"].tap(); app.tabBars.buttons["Картирование"].tap()
        reveal("captureMappingAutomatic", app: app); XCTAssertTrue(app.staticTexts["Замеры: 2"].exists)
        app.buttons["projectPicker"].tap(); app.buttons["Не выбрано"].tap()
        XCTAssertTrue(app.buttons["Остаться"].waitForExistence(timeout: 5)); app.buttons["Остаться"].tap()
        XCTAssertTrue(app.staticTexts["Замеры: 2"].exists)
        // An isolated standalone journal stays empty even after adding draft originals.
        app.buttons["mappingServices"].tap(); app.buttons["Неназначенные измерения"].tap()
        XCTAssertTrue(app.staticTexts["Неназначенных измерений нет"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        save(app); saved(app); top(app)
        XCTAssertEqual(app.textFields["mappingZ"].value as? String, "393")
        reveal("captureMappingAutomatic", app: app); XCTAssertTrue(app.staticTexts["Замеры: 0"].exists)
        app.buttons["mappingJournal"].tap(); app.staticTexts["ПК 0+005"].tap()
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "pointMeasurement-"))
        revealMeasurements(rows, app: app)
        XCTAssertEqual(rows.count, 2)
        rows.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Исходный ручной ввод"].waitForExistence(timeout: 5))
        let originalDip = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "45,125")).firstMatch
        for _ in 0..<8 { if originalDip.exists { break }; scrollForm(app, up: true) }
        XCTAssertTrue(originalDip.exists)
        app.terminate(); app.launch(); app.buttons["mappingJournal"].tap(); app.staticTexts["ПК 0+005"].tap()
        revealMeasurements(rows, app: app); XCTAssertEqual(rows.count, 2)
    }
    @MainActor func testP32SetsEvidenceFaultsValidationResetAndOfflineReopen() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["FIELD_FORGE_TEST_RUN_ID"] = UUID().uuidString
        app.launchArguments = ["--ui-testing"]; app.launch()
        let project = "P32-\(String(UUID().uuidString.prefix(8)))"
        create("projectPicker", name: project, app: app); select("projectPicker", value: project, app: app)
        create("horizonPicker", name: "+393 м", app: app); select("horizonPicker", value: "+393 м", app: app)
        create("excavationPicker", name: "E", app: app); select("excavationPicker", value: "E", app: app)
        fill(app.textFields["mappingPicket"], "ПК 0+005", app: app)
        show(disclosure("Интервал и положение", app: app), app: app); disclosure("Интервал и положение", app: app).tap()
        fill(app.textFields["mappingStartPicket"], "5", app: app)
        fill(app.textFields["mappingEndPicket"], "10,5", app: app)
        show(app.buttons["mappingPosition"], app: app); app.buttons["mappingPosition"].tap(); app.buttons["Кровля"].tap()
        disclosure("Интервал и положение", app: app).tap()
        for index in 1...2 {
            reveal("captureMappingManual", app: app); app.buttons["captureMappingManual"].tap()
            XCTAssertTrue(app.textFields["manualDip"].waitForExistence(timeout: 5))
            fill(app.textFields["manualDip"], "\(40 + index)", app: app)
            fill(app.textFields["manualDirection"], "\(350 + index)", app: app)
            app.buttons["addMappingMeasurement"].tap()
        }
        top(app); show(disclosure("Системы трещин", app: app), app: app); disclosure("Системы трещин", app: app).tap()
        for index in 1...5 {
            show(app.buttons["addJointSet"], app: app); app.buttons["addJointSet"].tap()
            let edit = app.buttons["editJointSet-J\(index)"]; show(edit, app: app); edit.tap()
            XCTAssertTrue(app.textFields["geologyDip"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.textFields["geologyDip"].value as? String, "Не указано")
            fill(app.textFields["geologyDip"], "\(45 + index)", app: app)
            fill(app.textFields["geologyDirection"], "120,125", app: app)
            if index == 1 {
                app.buttons["geologyNorth"].tap(); app.buttons["Сеточный север"].tap()
                for evidence in 1...2 {
                    let toggle = app.switches["jointEvidence-\(evidence)"]; show(toggle, app: app)
                    toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
                    XCTAssertEqual(toggle.value as? String, "1")
                }
                fill(app.textFields["jointSpacing"], "0,25", app: app)
                fill(app.textFields["jointAperture"], "-1", app: app)
                XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "число ≥ 0")).firstMatch.exists)
            }
            back(app)
        }
        show(app.buttons["addJointSet"], app: app); XCTAssertFalse(app.buttons["addJointSet"].isEnabled)
        save(app)
        XCTAssertTrue(app.alerts["Картирование"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "J1:")).firstMatch.exists)
        app.buttons["Понятно"].tap()
        reveal("editJointSet-J1", app: app); app.buttons["editJointSet-J1"].tap()
        show(app.textFields["jointAperture"], app: app)
        XCTAssertEqual(app.textFields["jointAperture"].value as? String, "-1")
        fill(app.textFields["jointAperture"], "0,125", app: app)
        back(app)
        top(app); show(disclosure("Тектоника:", app: app), app: app); disclosure("Тектоника:", app: app).tap()
        for index in 1...2 {
            show(app.buttons["addTectonicStructure"], app: app); app.buttons["addTectonicStructure"].tap()
            let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "editTectonic-"))
            let row = rows.element(boundBy: index - 1); show(row, app: app); row.tap()
            XCTAssertTrue(app.textFields["geologyDip"].waitForExistence(timeout: 5))
            fill(app.textFields["geologyDip"], "65", app: app)
            fill(app.textFields["geologyDirection"], "210", app: app)
            app.buttons["geologyNorth"].tap(); app.buttons["Истинный север"].tap()
            fill(app.textFields["tectonicThickness"], "0,5", app: app)
            fill(app.textFields["tectonicPicket"], "\(6 + index)", app: app)
            back(app)
        }
        // Returning from the plan and temporary backgrounding retain geological drafts.
        top(app); app.buttons["selectHorizonPlan"].tap()
        XCTAssertTrue(app.buttons["Вернуться"].waitForExistence(timeout: 5)); app.buttons["Вернуться"].tap()
        XCUIDevice.shared.press(.home); app.activate()
        save(app); saved(app); top(app)
        XCTAssertTrue(app.buttons["projectPicker"].label.contains(project))
        XCTAssertEqual(app.textFields["mappingPicket"].value as? String, "Пикет: ПК 0+005 или метры")
        XCTAssertEqual(app.textFields["mappingZ"].value as? String, "393")
        top(app); show(disclosure("Системы трещин", app: app), app: app); XCTAssertTrue(disclosure("Системы трещин", app: app).label.contains("0/5"))
        top(app); show(disclosure("Тектоника:", app: app), app: app); XCTAssertTrue(disclosure("Тектоника:", app: app).label.contains("0"))
        top(app); fill(app.textFields["mappingPicket"], "ПК 0+010", app: app); save(app); saved(app)
        app.terminate(); app.launch()
        reviewP32Journal(app)
    }
    @MainActor private func journalValue(_ title: String, _ value: String, app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", title, value)).firstMatch
    }
    @MainActor private func reviewP32Journal(_ app: XCUIApplication) {
        app.buttons["mappingJournal"].tap()
        XCTAssertTrue(app.staticTexts["ПК 0+005"].waitForExistence(timeout: 5)); XCTAssertTrue(app.staticTexts["ПК 0+010"].exists)
        app.staticTexts["ПК 0+005"].tap()
        show(journalValue("Положение", "Кровля", app: app), app: app)
        for index in 1...5 { show(disclosure("J\(index) · интерпретация", app: app), app: app) }
        show(disclosure("J1 · интерпретация", app: app), app: app, upward: false); disclosure("J1 · интерпретация", app: app).tap()
        show(journalValue("Раскрытие, мм", "0.12500000", app: app), app: app)
        let links = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "jointSource-J1-"))
        show(links.element(boundBy: 1), app: app); XCTAssertEqual(links.count, 2)
        links.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Исходный ручной ввод"].waitForExistence(timeout: 5))
        back(app)
        show(disclosure("№1 · Разлом", app: app), app: app); disclosure("№1 · Разлом", app: app).tap()
        show(journalValue("Мощность, м", "0.50000000", app: app), app: app)
        show(disclosure("№1 · Разлом", app: app), app: app, upward: false); disclosure("№1 · Разлом", app: app).tap()
        show(disclosure("№2 · Разлом", app: app), app: app); disclosure("№2 · Разлом", app: app).tap()
        show(journalValue("Мощность, м", "0.50000000", app: app), app: app)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "P32 saved tectonic structures"; screenshot.lifetime = .keepAlways; add(screenshot)
        back(app); app.staticTexts["ПК 0+010"].tap()
        XCTAssertFalse(disclosure("J1 · интерпретация", app: app).exists)
    }
    @MainActor private func disclosure(_ title: String, app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
    }
    @MainActor private func fill(_ field: XCUIElement, _ text: String, app: XCUIApplication) {
        show(field, app: app); field.tap()
        let old = field.value as? String ?? ""
        if old != field.placeholderValue { field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count)) }
        field.typeText(text); dismissKeyboard(app)
    }
    @MainActor private func show(_ element: XCUIElement, app: XCUIApplication, upward: Bool = true) {
        for _ in 0..<24 {
            if element.exists && element.isHittable { return }
            scrollForm(app, up: upward)
        }
        XCTFail("Element not visible: \(element)\n\(app.debugDescription)")
    }
    @MainActor private func back(_ app: XCUIApplication) { app.navigationBars.buttons.element(boundBy: 0).tap() }
    @MainActor private func revealMeasurements(_ rows: XCUIElementQuery, app: XCUIApplication) {
        for _ in 0..<8 {
            if rows.firstMatch.exists && rows.firstMatch.isHittable { return }
            scrollForm(app, up: true)
        }
        XCTFail("Point originals not visible")
    }
    @MainActor private func reveal(_ identifier: String, app: XCUIApplication) {
        top(app)
        for _ in 0..<12 {
            if app.buttons[identifier].exists && app.buttons[identifier].isHittable { return }
            scrollForm(app, up: true)
        }
        XCTAssertTrue(app.buttons[identifier].isHittable)
    }
    @MainActor private func top(_ app: XCUIApplication) {
        let field = app.textFields["mappingPicket"]
        for _ in 0..<16 {
            let viewport = app.collectionViews.firstMatch.frame
            if field.exists && viewport.contains(CGPoint(x: field.frame.midX, y: field.frame.midY)) && field.isHittable { return }
            scrollForm(app, up: false)
        }
    }
    @MainActor private func scrollForm(_ app: XCUIApplication, up: Bool) {
        let form = app.collectionViews.firstMatch
        let start = form.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: up ? 0.8 : 0.3))
        let end = form.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.55))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
    }
    @MainActor private func create(_ picker: String, name: String, app: XCUIApplication) {
        let button = app.buttons["manage-\(picker)"]; XCTAssertTrue(button.waitForExistence(timeout: 10)); button.tap()
        let field = app.textFields[picker == "horizonPicker" ? "contextElevation" : "contextName"]; XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText(picker == "horizonPicker" ? "393" : name)
        dismissKeyboard(app)
        app.buttons["saveContext"].tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: button)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
    }
    @MainActor private func select(_ picker: String, value: String, app: XCUIApplication) {
        app.buttons[picker].tap(); app.buttons[value].tap()
    }
    @MainActor private func dismissKeyboard(_ app: XCUIApplication) { if app.buttons["Готово"].exists { app.buttons["Готово"].tap() } }
    @MainActor private func save(_ app: XCUIApplication) {
        let button = app.buttons["saveMappingObservation"]
        for _ in 0..<16 { if button.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(button.isHittable); button.tap()
    }
    @MainActor private func saved(_ app: XCUIApplication) {
        XCTAssertTrue(app.alerts["Наблюдение сохранено"].waitForExistence(timeout: 5)); app.buttons["Продолжить"].tap()
    }
}
