import XCTest

final class FieldForgeUITests: XCTestCase {
    @MainActor func testManualEntrySaveJournalRelaunchAndExport() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        let note = "Phase2-\(UUID().uuidString)"
        app.launch()
        let mode = app.segmentedControls["measurementMode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 10))
        mode.buttons["Геологический компас"].tap()
        let save = app.buttons["saveManualButton"]
        XCTAssertFalse(save.isEnabled)
        let dip = app.textFields["manualDip"]
        dip.tap(); dip.typeText("45,25")
        let direction = app.textFields["manualDirection"]
        direction.tap(); direction.typeText("360")
        app.buttons["Готово"].tap()
        for _ in 0..<5 {
            if app.textFields["manualNotes"].isHittable || app.textViews["manualNotes"].isHittable { break }
            app.swipeUp()
        }
        let notes = app.textFields["manualNotes"].exists ? app.textFields["manualNotes"] : app.textViews["manualNotes"]
        notes.tap(); notes.typeText(note)
        app.buttons["Готово"].tap()
        XCTAssertTrue(save.isEnabled)
        save.tap(); XCTAssertFalse(save.isEnabled)
        capture("Manual measurement")
        app.tabBars.buttons["Журнал"].tap()
        let source = "Ручной ввод · геологический компас"
        XCTAssertTrue(app.staticTexts[source].firstMatch.waitForExistence(timeout: 5))
        app.cells.containing(.staticText, identifier: source).firstMatch.tap()
        XCTAssertTrue(app.staticTexts[note].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Сенсорная диагностика отсутствует."].exists)
        app.terminate(); app.launch()
        app.tabBars.buttons["Журнал"].tap()
        app.cells.containing(.staticText, identifier: source).firstMatch.tap()
        XCTAssertTrue(app.staticTexts[note].waitForExistence(timeout: 5))
        app.tabBars.buttons["Настройки"].tap()
        let export = app.buttons["exportButton"]
        for _ in 0..<8 {
            if export.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(export.isEnabled); export.tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 5)
                      || app.buttons["Copy"].exists || app.buttons["Скопировать"].exists)
        capture("Manual CSV Share Sheet")
    }
    @MainActor func testSimulatorHoldSaveJournalRelaunchAndExport() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.staticTexts["mockBanner"].waitForExistence(timeout: 10))
        let save = app.buttons["saveButton"]
        XCTAssertFalse(save.isEnabled)
        let hold = app.buttons["holdButton"]
        XCTAssertTrue(hold.waitForExistence(timeout: 3)); XCTAssertTrue(hold.isEnabled)
        capture("Measurement")
        hold.tap()
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertFalse(save.isEnabled)
        app.tabBars.buttons["Журнал"].tap()
        XCTAssertTrue(app.staticTexts["DEMO · Синтетическая запись"].firstMatch.waitForExistence(timeout: 5))
        capture("Journal")
        app.terminate(); app.launch()
        app.tabBars.buttons["Журнал"].tap()
        XCTAssertTrue(app.staticTexts["DEMO · Синтетическая запись"].firstMatch.waitForExistence(timeout: 5))
        app.tabBars.buttons["Настройки"].tap()
        capture("Settings")
        let export = app.buttons["exportButton"]
        for _ in 0..<8 {
            if export.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(export.isHittable); XCTAssertTrue(export.isEnabled)
        export.tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 5)
                      || app.buttons["Copy"].exists || app.buttons["Скопировать"].exists)
        capture("CSV Share Sheet")
    }
    @MainActor private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
