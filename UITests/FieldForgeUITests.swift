import XCTest

final class FieldForgeUITests: XCTestCase {
    @MainActor func testManualEntrySaveJournalRelaunchAndExport() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        let note = "Phase2-\(UUID().uuidString)"
        app.launch()
        openService("Измерение", in: app)
        let mode = app.segmentedControls["measurementMode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 10))
        mode.buttons["Геологический компас"].tap()
        let save = app.buttons["saveManualButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 10))
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
        openService("Неназначенные измерения", in: app, relaunch: true)
        let source = "Ручной ввод · геологический компас"
        XCTAssertTrue(app.staticTexts[source].firstMatch.waitForExistence(timeout: 5))
        app.cells.containing(.staticText, identifier: source).firstMatch.tap()
        XCTAssertTrue(app.staticTexts[note].waitForExistence(timeout: 5))
        let diagnostics = app.staticTexts["Сенсорная диагностика отсутствует."]
        for _ in 0..<5 {
            if diagnostics.exists { break }
            app.swipeUp()
        }
        XCTAssertTrue(diagnostics.exists)
        openService("Неназначенные измерения", in: app, relaunch: true)
        app.cells.containing(.staticText, identifier: source).firstMatch.tap()
        XCTAssertTrue(app.staticTexts[note].waitForExistence(timeout: 5))
        openService("Настройки", in: app, relaunch: true)
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
        openService("Измерение", in: app)
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
        openService("Неназначенные измерения", in: app, relaunch: true)
        XCTAssertTrue(app.staticTexts["DEMO · Синтетическая запись"].firstMatch.waitForExistence(timeout: 5))
        capture("Journal")
        openService("Неназначенные измерения", in: app, relaunch: true)
        XCTAssertTrue(app.staticTexts["DEMO · Синтетическая запись"].firstMatch.waitForExistence(timeout: 5))
        openService("Настройки", in: app, relaunch: true)
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
    @MainActor private func openService(_ name: String, in app: XCUIApplication, relaunch: Bool = false) {
        if relaunch { app.terminate(); app.launch() }
        let menu = app.buttons["mappingServices"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10)); menu.tap()
        app.buttons[name].tap()
    }
    @MainActor private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
