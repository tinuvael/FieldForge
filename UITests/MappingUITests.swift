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
    @MainActor private func top(_ app: XCUIApplication) {
        for _ in 0..<16 { if app.textFields["mappingPicket"].isHittable { return }; app.swipeDown() }
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
