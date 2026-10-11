import XCTest

final class FieldForgeUITests: XCTestCase {
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
