import XCTest
import UIKit

final class MappingUITests: XCTestCase {
    @MainActor func testFinalPolishQuickRMRBasicWithoutRepeatedDescriptions() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]
        app.launchEnvironment["FIELD_FORGE_TEST_RUN_ID"] = UUID().uuidString; app.launch()
        let rmr = disclosure("RMR89 ·", app: app); show(rmr, app: app); rmr.tap()
        let basis = app.buttons["rmrStrengthBasis"]; show(basis, app: app); basis.tap()
        app.buttons["Is(50) — точечное нагружение"].tap()
        for (key, option) in [("strength", "4–10 · 12 балл."), ("rqd", "50–75 · 13 балл."),
            ("spacing", "0,2–0,6 · 10 балл."), ("persistence", "1–3 · 4 балл."),
            ("aperture", "0,1–1 · 4 балл."), ("roughness", "Слегка шероховатая · 3 балл."),
            ("infill", "Нет · 6 балл."), ("weathering", "Слабо выветрелые · 5 балл."), ("groundwater", "Мокро · 7 балл.")] {
            let picker = app.buttons["rmrCategory-" + key]; show(picker, app: app); picker.tap()
            app.buttons[option].tap()
        }
        let result = app.staticTexts["rmrBasicResult"]; show(result, app: app)
        XCTAssertEqual(result.label, "RMR89 (базовый): 64")
        XCTAssertTrue(app.staticTexts["Класс массива: II — хорошее качество"].exists)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Final quick RMR89 basic 64"; shot.lifetime = .keepAlways; add(shot)
    }
    @MainActor func testFinalPolishWedgesNumericKeyboardAndAzimuthTransitions() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]
        app.launchEnvironment["FIELD_FORGE_TEST_RUN_ID"] = UUID().uuidString; app.launch()
        app.tabBars.buttons["Клинья"].tap()
        let axis = app.textFields["wedgeAxis"]
        XCTAssertTrue(axis.waitForExistence(timeout: 5)); axis.tap(); axis.typeText("285")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let done = app.buttons["wedgesKeyboardDone"]
        XCTAssertTrue(done.isHittable)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Final Wedges numeric keyboard and native Done"; shot.lifetime = .keepAlways; add(shot)
        if app.keys["1"].exists { XCTAssertLessThan(done.frame.maxY, app.keys["1"].frame.minY) }
        done.tap()
        XCTAssertFalse(app.keyboards.firstMatch.exists); XCTAssertEqual(axis.value as? String, "285°")
        axis.tap(); XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(axis.value as? String, "285")
        done.tap(); XCTAssertEqual(axis.value as? String, "285°")
        let form = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        form.name = "Final compact Wedges form"; form.lifetime = .keepAlways; add(form)
    }
    @MainActor func testFinalPolishCoordinatesAndDefaultSingleExcelShare() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]
        app.launchEnvironment["FIELD_FORGE_TEST_RUN_ID"] = UUID().uuidString; app.launch()
        let project = "Полевой-\(UUID().uuidString.prefix(6))"
        create("projectPicker", name: project, app: app); select("projectPicker", value: project, app: app)
        app.buttons["manage-horizonPicker"].tap()
        fill(app.textFields["contextElevation"], "393", app: app)
        app.buttons["saveContext"].tap(); app.buttons["Закрыть"].tap()
        select("horizonPicker", value: "+393 м", app: app)
        create("excavationPicker", name: "Штрек", app: app); select("excavationPicker", value: "Штрек", app: app)
        fill(app.textFields["mappingPicket"], "12+1,8", app: app)
        let x = app.textFields["mappingX"]; show(x, app: app)
        fill(x, "123,123456789", app: app); dismissKeyboard(app)
        XCTAssertEqual(x.value as? String, "123,1")
        x.tap(); XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(x.value as? String, "123,123456789"); dismissKeyboard(app)
        let coordinates = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        coordinates.name = "Final Mapping coordinate rows"; coordinates.lifetime = .keepAlways; add(coordinates)
        save(app); saved(app); top(app)
        app.buttons["mappingJournal"].tap(); app.buttons["mappingExportAction"].tap()
        let count = app.staticTexts["mappingExportPointCount"]
        XCTAssertTrue(count.waitForExistence(timeout: 5)); XCTAssertEqual(count.label, "Наблюдений: 1")
        let share = app.buttons["mappingExportShare"]; XCTAssertEqual(share.label, "Экспортировать Excel")
        share.tap()
        let activity = app.otherElements["ActivityListView"]
        XCTAssertTrue(activity.waitForExistence(timeout: 15))
        let title = activity.otherElements["LP.CaptionBar.BottomCaption"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(title.label, "FieldForge-Mapping.xlsx")
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label ENDSWITH %@", ".csv")).firstMatch.exists)
        let excel = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        excel.name = "Final single Excel workbook in native share sheet"; excel.lifetime = .keepAlways; add(excel)
        activity.buttons.firstMatch.tap()
        XCTAssertTrue(share.waitForExistence(timeout: 5))
    }
    /// Simulator DEMO north cannot become a geological representative. Exercise the real
    /// nested presentation/cancel path, then manual acceptance; sensor conversion is a core test.
    @MainActor func testThirdReviewEditorOwnershipAfterNestedMeasurementCancel() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["FIELD_FORGE_TEST_RUN_ID"] = UUID().uuidString
        app.launchArguments = ["--ui-testing"]; app.launch()
        let project = "Third-\(UUID().uuidString.prefix(8))"
        create("projectPicker", name: project, app: app); select("projectPicker", value: project, app: app)
        app.buttons["manage-horizonPicker"].tap()
        fill(app.textFields["contextElevation"], "393", app: app)
        app.buttons["saveContext"].tap()
        app.buttons["Закрыть"].tap()
        select("horizonPicker", value: "+393 м", app: app)
        create("excavationPicker", name: "Штрек", app: app); select("excavationPicker", value: "Штрек", app: app)
        fill(app.textFields["mappingPicket"], "12,18", app: app)
        for index in 1...5 {
            show(app.buttons["addJointSet"], app: app); app.buttons["addJointSet"].tap()
            XCTAssertTrue(app.navigationBars["Система J\(index)"].waitForExistence(timeout: 5), app.debugDescription)
            if index == 1 {
                app.buttons["Замерить iPhone"].tap()
                XCTAssertTrue(app.buttons["mappingHold"].waitForExistence(timeout: 5))
                app.buttons["mappingHold"].tap()
                XCTAssertTrue(app.buttons["closeMappingMeasurement"].isHittable)
                app.buttons["closeMappingMeasurement"].tap()
                XCTAssertTrue(app.navigationBars["Система J1"].waitForExistence(timeout: 5))
            }
            fill(app.textFields["geologyDirection"], "132,4", app: app)
            fill(app.textFields["geologyDip"], "48,1", app: app)
            app.buttons["Принять"].tap()
            XCTAssertTrue(app.buttons["editJointSet-J\(index)"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Черновик точки изменился")).firstMatch.exists)
        }
        save(app); saved(app); top(app)
        app.buttons["mappingJournal"].tap()
        XCTAssertTrue(app.staticTexts["ПК 12+1,8"].firstMatch.waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        app.buttons["mappingJournal"].tap()
        XCTAssertTrue(app.staticTexts["ПК 12+1,8"].firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor func testP61DistanceUnsupportedClosePreservesMappingDraft() throws {
        continueAfterFailure = false
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchEnvironment["FIELD_FORGE_TEST_RUN_ID"] = UUID().uuidString
        app.launchArguments = ["--ui-testing"]; app.launch()
        fill(app.textFields["mappingPicket"], "17", app: app)
        fill(app.textFields["mappingX"], "123.25", app: app)
        for close in ["distanceClose", "distanceDone"] {
            reveal("mappingDistance", app: app); app.buttons["mappingDistance"].tap()
            let status = app.staticTexts["distanceStatus"]
            XCTAssertTrue(status.waitForExistence(timeout: 10))
            XCTAssertTrue(status.label.contains("недоступно"))
            XCTAssertFalse(app.buttons["distanceSelectPoint"].isEnabled)
            XCTAssertFalse(app.staticTexts["distanceResult"].exists)
            app.buttons["distanceRetake"].tap()
            XCTAssertTrue(status.label.contains("недоступно"))
            if close == "distanceDone" {
                XCUIDevice.shared.orientation = .landscapeLeft
                XCTAssertTrue(app.buttons["distanceClose"].isHittable)
                app.scrollViews["distanceControls"].swipeUp()
            }
            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screenshot.name = "P61 unsupported AR utility"; screenshot.lifetime = .keepAlways; add(screenshot)
            app.buttons[close].tap()
            XCUIDevice.shared.orientation = .portrait
            top(app); XCTAssertEqual(app.textFields["mappingPicket"].value as? String, "17")
            XCTAssertEqual(app.textFields["mappingX"].value as? String, "123.25")
            XCTAssertFalse(app.staticTexts["mappingLastDistance"].exists)
        }
    }

    @MainActor func testP51MappingCSVPreviewShareCancelAndDraftRetention() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["FIELD_FORGE_TEST_RUN_ID"] = UUID().uuidString
        app.launchArguments = ["--ui-testing"]; app.launch()
        let project = "Выгрузка-\(UUID().uuidString.prefix(8))"
        create("projectPicker", name: project, app: app); select("projectPicker", value: project, app: app)
        create("horizonPicker", name: "+393 м", app: app); select("horizonPicker", value: "+393 м", app: app)
        create("excavationPicker", name: "Штрек", app: app); select("excavationPicker", value: "Штрек", app: app)
        let picket = app.textFields["mappingPicket"]
        picket.tap(); picket.typeText("5"); dismissKeyboard(app); save(app); saved(app); top(app)
        picket.tap(); picket.typeText("10"); dismissKeyboard(app)
        app.buttons["mappingJournal"].tap()
        XCTAssertTrue(app.buttons["mappingExportAction"].waitForExistence(timeout: 5)); app.buttons["mappingExportAction"].tap()
        let count = app.staticTexts["mappingExportPointCount"]
        XCTAssertTrue(count.waitForExistence(timeout: 10)); XCTAssertEqual(count.label, "Наблюдений: 1")
        let share = app.buttons["mappingExportShare"]; XCTAssertEqual(share.label, "Экспортировать Excel")
        photoReveal(share, app: app); share.tap()
        let activity = app.otherElements["ActivityListView"]
        let cancel = activity.buttons.firstMatch
        XCTAssertTrue(activity.waitForExistence(timeout: 10)); XCTAssertTrue(cancel.waitForExistence(timeout: 5)); cancel.tap()
        photoReveal(share, app: app); share.tap(); XCTAssertTrue(cancel.waitForExistence(timeout: 10)); cancel.tap()
        let advanced = app.buttons["Дополнительные параметры"]
        photoReveal(advanced, app: app, upward: false); advanced.tap()
        let format = app.buttons["mappingExportFormat"]
        photoReveal(format, app: app); format.tap(); app.buttons["CSV"].tap()
        XCTAssertEqual(count.label, "Наблюдений: 1")
        photoReveal(share, app: app); XCTAssertEqual(share.label, "Экспортировать CSV"); share.tap()
        XCTAssertTrue(cancel.waitForExistence(timeout: 10)); cancel.tap()
        photoReveal(format, app: app, upward: false); format.tap(); app.buttons["Excel (.xlsx)"].tap()
        photoReveal(share, app: app); share.tap(); XCTAssertTrue(cancel.waitForExistence(timeout: 10)); cancel.tap()
        back(app); back(app); top(app)
        XCTAssertEqual(picket.value as? String, "10")
    }
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
        XCTAssertTrue(heading("Наблюдение · актуальная версия", app: app).waitForExistence(timeout: 5))
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
        XCTAssertTrue(heading("Замеры: 1", app: app).waitForExistence(timeout: 5))
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
        add.tap(); XCTAssertTrue(heading("Замеры: 2", app: app).waitForExistence(timeout: 5))
        app.buttons["captureMappingAutomatic"].tap()
        XCTAssertTrue(app.buttons["closeMappingMeasurement"].waitForExistence(timeout: 5))
        app.buttons["closeMappingMeasurement"].tap()
        XCTAssertTrue(heading("Замеры: 2", app: app).waitForExistence(timeout: 5))
        top(app); app.buttons["selectHorizonPlan"].tap()
        XCTAssertTrue(app.buttons["Вернуться"].waitForExistence(timeout: 5)); app.buttons["Вернуться"].tap()
        app.tabBars.buttons["План"].tap(); app.tabBars.buttons["Картирование"].tap()
        reveal("captureMappingAutomatic", app: app); XCTAssertTrue(heading("Замеры: 2", app: app).exists)
        app.buttons["projectPicker"].tap(); app.buttons["Не выбрано"].tap()
        XCTAssertTrue(app.buttons["Остаться"].waitForExistence(timeout: 5)); app.buttons["Остаться"].tap()
        XCTAssertTrue(heading("Замеры: 2", app: app).exists)
        // An isolated standalone journal stays empty even after adding draft originals.
        app.buttons["mappingServices"].tap(); app.buttons["Неназначенные измерения"].tap()
        XCTAssertTrue(app.staticTexts["Неназначенных измерений нет"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        save(app); saved(app); top(app)
        XCTAssertEqual(app.textFields["mappingZ"].value as? String, "393")
        reveal("captureMappingAutomatic", app: app); XCTAssertTrue(heading("Замеры: 0", app: app).exists)
        app.buttons["mappingJournal"].tap(); app.staticTexts["ПК 0+005"].tap()
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "pointMeasurement-"))
        revealMeasurements(rows, app: app)
        XCTAssertEqual(rows.count, 2)
        rows.firstMatch.tap()
        XCTAssertTrue(heading("Исходный ручной ввод", app: app).waitForExistence(timeout: 5))
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
        top(app); fill(app.textFields["mappingPicket"], "ПК 0+005", app: app)
        show(disclosure("Интервал и положение", app: app), app: app); disclosure("Интервал и положение", app: app).tap()
        fill(app.textFields["mappingStartPicket"], "5", app: app)
        fill(app.textFields["mappingEndPicket"], "10,5", app: app)
        show(app.buttons["mappingPosition"], app: app); app.buttons["mappingPosition"].tap(); app.buttons["Кровля"].tap()
        show(app.staticTexts["mappingWallConvention"], app: app)
        XCTAssertEqual(app.staticTexts["mappingWallConvention"].label, "Левая и правая стенка — по направлению возрастания пикетажа.")
        show(disclosure("Интервал и положение", app: app), app: app, upward: false)
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
        for index in 1...5 {
            show(app.buttons["addTectonicStructure"], app: app); app.buttons["addTectonicStructure"].tap()
            let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "editTectonic-"))
            let row = rows.element(boundBy: index - 1); show(row, app: app); row.tap()
            XCTAssertTrue(app.textFields["geologyDip"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.textFields["geologyDip"].value as? String, "Не указано")
            XCTAssertEqual(app.textFields["geologyDirection"].value as? String, "Не указано")
            if index <= 2 {
                fill(app.textFields["geologyDip"], "65", app: app)
                fill(app.textFields["geologyDirection"], "210", app: app)
                app.buttons["geologyNorth"].tap(); app.buttons["Истинный север"].tap()
            } else if index == 3 {
                fill(app.textFields["geologyDip"], "91", app: app)
                XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "geologyOrientationError").firstMatch.exists)
                fill(app.textFields["geologyDip"], "45", app: app)
                show(app.staticTexts["Неполная ориентировка: азимут падения не определён"], app: app)
            } else if index == 4 {
                fill(app.textFields["geologyDirection"], "361", app: app)
                XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "geologyOrientationError").firstMatch.exists)
                fill(app.textFields["geologyDirection"], "360", app: app)
                app.buttons["geologyNorth"].tap(); app.buttons["Сеточный север"].tap()
                show(app.staticTexts["Неполная ориентировка: угол падения не указан"], app: app)
            } else {
                show(app.staticTexts["Ориентировка не определена"], app: app)
            }
            fill(app.textFields["tectonicThickness"], "0,5", app: app)
            fill(app.textFields["tectonicPicket"], "\(6 + index)", app: app)
            if index == 5 {
                fill(multilineInput("tectonicPosition", app: app), "У кровли", app: app)
                fill(multilineInput("tectonicDescription", app: app), "След разлома без замера", app: app)
            }
            back(app)
        }
        // The distance utility must also preserve J1–J5, tectonics and original readings.
        reveal("mappingDistance", app: app); app.buttons["mappingDistance"].tap()
        XCTAssertTrue(app.buttons["distanceDone"].waitForExistence(timeout: 10))
        app.buttons["distanceDone"].tap()
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
        XCTAssertTrue(heading("Исходный ручной ввод", app: app).waitForExistence(timeout: 5))
        back(app)
        for index in 1...5 {
            let row = disclosure("№\(index) · Разлом", app: app)
            show(row, app: app); row.tap()
            if index <= 2 {
                show(journalValue("Мощность, м", "0.50000000", app: app), app: app)
            } else if index == 3 {
                show(app.staticTexts["Неполная ориентировка: азимут падения не определён"], app: app)
                show(journalValue("Угол падения, °", "45", app: app), app: app)
                show(journalValue("Азимут падения, °", "Не определён", app: app), app: app)
            } else if index == 4 {
                show(app.staticTexts["Неполная ориентировка: угол падения не указан"], app: app)
                show(journalValue("Угол падения, °", "Не определён", app: app), app: app)
                show(journalValue("Азимут падения, °", "360", app: app), app: app)
                show(journalValue("Вид севера", "Сеточный север", app: app), app: app)
            } else {
                show(app.staticTexts["Ориентировка не определена"], app: app)
                show(journalValue("Угол падения, °", "Не определён", app: app), app: app)
                show(journalValue("Азимут падения, °", "Не определён", app: app), app: app)
                show(journalValue("Мощность, м", "0.50000000", app: app), app: app)
                show(journalValue("Пикет структуры", "11", app: app), app: app)
                show(journalValue("Положение структуры", "У кровли", app: app), app: app)
                show(journalValue("Описание", "След разлома без замера", app: app), app: app)
                let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                screenshot.name = "P32 saved tectonic structure without orientation"; screenshot.lifetime = .keepAlways; add(screenshot)
            }
            show(row, app: app, upward: false); row.tap()
        }
        back(app); app.staticTexts["ПК 0+010"].tap()
        XCTAssertFalse(disclosure("J1 · интерпретация", app: app).exists)
    }
    @MainActor func testP32bRatingsPartialFailureCompleteQResetAndJournalReopen() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchEnvironment["FIELD_FORGE_TEST_RUN_ID"] = UUID().uuidString
        app.launchArguments = ["--ui-testing"]; app.launch()
        let project = "Q-" + String(UUID().uuidString.prefix(6)), excavation = "Q-штрек"
        create("projectPicker", name: project, app: app); select("projectPicker", value: project, app: app)
        create("horizonPicker", name: "+393 м", app: app); select("horizonPicker", value: "+393 м", app: app)
        create("excavationPicker", name: excavation, app: app); select("excavationPicker", value: excavation, app: app)
        top(app); fill(app.textFields["mappingPicket"], "5", app: app)
        let qSection = disclosure("Barton Q", app: app); show(qSection, app: app); qSection.tap()
        fill(app.textViews["qRQD"], "0,125", app: app)
        show(app.buttons["qRQDSource"], app: app); app.buttons["qRQDSource"].tap()
        app.buttons["Измерено по керну"].tap()
        show(app.buttons["qLocation"], app: app); app.buttons["qLocation"].tap(); app.buttons["Обычный участок · Jn ×1"].tap()
        show(app.buttons["qContact"], app: app); app.buttons["qContact"].tap(); app.buttons["a — контакт стенок"].tap()
        let choices = [("jn", "Jn —", "F ·"), ("jr", "Jr —", "B ·"), ("ja", "Ja —", "C ·"),
                       ("jw", "Jw —", "A ·"), ("srf", "SRF —", "G ·")]
        for (parameter, title, rowPrefix) in choices {
            let group = disclosure(title, app: app); show(group, app: app); group.tap()
            let picker = app.buttons["qCategory-" + parameter]; show(picker, app: app); picker.tap()
            let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", rowPrefix)).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5), app.debugDescription); row.tap()
            show(group, app: app, upward: false); group.tap()
        }
        fill(app.textViews["qAssessmentSource"], "UI field notebook", app: app)
        show(app.staticTexts["qResult"], app: app); XCTAssertTrue(app.staticTexts["qResult"].label.contains("1,66667"))
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); screenshot.name = "NGI 2025 Q result and RQD minimum convention"; screenshot.lifetime = .keepAlways; add(screenshot)
        show(qSection, app: app, upward: false); qSection.tap()
        let rmrSection = disclosure("RMR", app: app); show(rmrSection, app: app); rmrSection.tap()
        XCTAssertTrue(app.buttons["rmrCategory-rqd"].exists)
        let rmrEvidence = app.buttons["Измеренные значения и сведения об оценке"]
        show(rmrEvidence, app: app); rmrEvidence.tap()
        fill(app.textViews["rmrStrength"], "-1", app: app)
        save(app)
        XCTAssertTrue(app.buttons["Понятно"].waitForExistence(timeout: 5)); app.buttons["Понятно"].tap()
        show(app.textViews["rmrStrength"], app: app, upward: false)
        XCTAssertEqual(app.textViews["rmrStrength"].value as? String, "-1")
        fill(app.textViews["rmrStrength"], "120", app: app)
        show(rmrSection, app: app, upward: false); rmrSection.tap()
        save(app); saved(app); top(app)
        XCTAssertTrue(app.buttons["projectPicker"].label.contains(project)); XCTAssertTrue(app.buttons["excavationPicker"].label.contains(excavation))
        XCTAssertEqual(app.textFields["mappingPicket"].value as? String, "Пикет: ПК 0+005 или метры")
        XCTAssertEqual(app.textFields["mappingZ"].value as? String, "393")
        show(qSection, app: app); qSection.tap()
        show(app.textViews["qRQD"], app: app)
        XCTAssertEqual(app.textViews["qRQD"].value as? String, "Не указано")
        show(qSection, app: app, upward: false); qSection.tap()
        top(app); fill(app.textFields["mappingPicket"], "10", app: app); save(app); saved(app)
        app.terminate(); app.launch()
        app.buttons["mappingJournal"].tap(); app.staticTexts["5"].tap()
        let savedQ = disclosure("Barton Q ·", app: app); show(savedQ, app: app); savedQ.tap()
        show(app.staticTexts["qResult"], app: app); XCTAssertTrue(app.staticTexts["qResult"].label.contains("1,66667"))
        show(savedQ, app: app, upward: false); savedQ.tap()
        let savedRMR = disclosure("RMR89 ·", app: app); show(savedRMR, app: app); savedRMR.tap()
        XCTAssertTrue(app.staticTexts["savedRMRUnavailable"].exists)
    }
    @MainActor func testP33CorrectionHistoryPlanMoveEvidenceAndRelaunch() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["FIELD_FORGE_TEST_RUN_ID"] = UUID().uuidString
        app.launchEnvironment["P2_PLAN_A"] = "0\nSECTION\n2\nENTITIES\n0\nLINE\n10\n100\n20\n200\n11\n300\n21\n400\n0\nENDSEC\n0\nEOF\n"
        app.launchArguments = ["--ui-testing"]; app.launch()
        let project = "P33-\(UUID().uuidString.prefix(8))"
        create("projectPicker", name: project, app: app); select("projectPicker", value: project, app: app)
        create("horizonPicker", name: "+393 м", app: app); select("horizonPicker", value: "+393 м", app: app)
        create("excavationPicker", name: "E", app: app); select("excavationPicker", value: "E", app: app)
        top(app); fill(app.textFields["mappingPicket"], "5", app: app)
        reveal("captureMappingManual", app: app); app.buttons["captureMappingManual"].tap()
        fill(app.textFields["manualDip"], "45,125", app: app); fill(app.textFields["manualDirection"], "270", app: app)
        app.buttons["addMappingMeasurement"].tap()
        show(disclosure("Системы трещин", app: app), app: app); disclosure("Системы трещин", app: app).tap()
        show(app.buttons["addJointSet"], app: app); app.buttons["addJointSet"].tap()
        app.buttons["editJointSet-J1"].tap()
        fill(app.textFields["geologyDip"], "46", app: app); fill(app.textFields["geologyDirection"], "120", app: app)
        let evidence = app.switches["jointEvidence-1"]; show(evidence, app: app)
        evidence.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap(); back(app)
        show(disclosure("Тектоника", app: app), app: app); disclosure("Тектоника", app: app).tap()
        show(app.buttons["addTectonicStructure"], app: app); app.buttons["addTectonicStructure"].tap()
        let fault = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "editTectonic-")).firstMatch
        show(fault, app: app); fault.tap(); fill(app.textFields["tectonicThickness"], "0,5", app: app); back(app)
        top(app); reveal("selectHorizonPlan", app: app); app.buttons["selectHorizonPlan"].tap()
        app.buttons["P2_PLAN_A"].tap(); XCTAssertTrue(app.textFields["planVersion"].waitForExistence(timeout: 5))
        fill(app.textFields["planVersion"], "A", app: app); app.buttons["savePlanImport"].tap()
        XCTAssertTrue(app.staticTexts["P2_PLAN_A.dxf"].waitForExistence(timeout: 10)); app.staticTexts["P2_PLAN_A.dxf"].tap()
        let canvas = app.otherElements["planCanvas"]; XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap(); app.buttons["confirmPlanXY"].tap()
        save(app); saved(app)
        app.buttons["mappingJournal"].tap()
        let records = app.collectionViews["journalObservations"].buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "journalRecord-"))
        XCTAssertEqual(records.count, 1); let recordID = records.firstMatch.identifier; records.firstMatch.tap()
        app.buttons["editMappingObservation"].tap()
        XCTAssertTrue(app.textFields["correctionPicket"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["correctionPicket"].value as? String, "5")
        fill(app.textFields["correctionPicket"], "17,125", app: app)
        app.buttons["cancelMappingCorrection"].tap()
        XCTAssertTrue(app.buttons["Продолжить редактирование"].waitForExistence(timeout: 5)); app.buttons["Продолжить редактирование"].tap()
        show(app.buttons["saveMappingCorrection"], app: app); app.buttons["saveMappingCorrection"].tap()
        XCTAssertTrue(app.staticTexts["correctionError"].waitForExistence(timeout: 5))
        show(app.textViews["correctionReason"], app: app, upward: false)
        fill(app.textViews["correctionReason"], "Исправлены пикет, J1, мощность и положение", app: app)
        show(disclosure("Системы трещин", app: app), app: app); disclosure("Системы трещин", app: app).tap()
        show(app.buttons["editJointSet-J1"], app: app); app.buttons["editJointSet-J1"].tap()
        XCTAssertEqual(app.textFields["geologyDip"].value as? String, "46")
        fill(app.textFields["geologyDip"], "52", app: app)
        XCTAssertEqual(app.switches["jointEvidence-1"].value as? String, "1"); back(app)
        show(disclosure("Тектоника", app: app), app: app); disclosure("Тектоника", app: app).tap()
        show(fault, app: app); fault.tap(); fill(app.textFields["tectonicThickness"], "0,75", app: app); back(app)
        show(app.buttons["correctionSelectPlan"], app: app, upward: false); app.buttons["correctionSelectPlan"].tap()
        app.staticTexts["P2_PLAN_A.dxf"].tap(); XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["planPoints"].label.contains("1"))
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)).tap(); app.buttons["confirmPlanXY"].tap()
        show(app.buttons["saveMappingCorrection"], app: app); app.buttons["saveMappingCorrection"].tap()
        XCTAssertTrue(app.buttons["editMappingObservation"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["mappingRevisionBadge"].label.hasPrefix("Версия 2"))
        app.buttons["mappingRevisionHistory"].tap(); app.buttons["compareRevision-2"].tap()
        XCTAssertTrue(app.staticTexts["J1 · ориентация и север"].waitForExistence(timeout: 5)); back(app)
        app.buttons["mappingOriginalVersion"].tap()
        XCTAssertFalse(app.buttons["editMappingObservation"].exists)
        XCTAssertTrue(heading("Исторический снимок · только просмотр", app: app).exists)
        back(app); back(app)
        app.buttons["editMappingObservation"].tap()
        fill(app.textViews["correctionReason"], "Проверка повторного исправления", app: app)
        fill(app.textFields["correctionPicket"], "25", app: app)
        show(app.buttons["saveMappingCorrection"], app: app); app.buttons["saveMappingCorrection"].tap()
        XCTAssertTrue(app.buttons["editMappingObservation"].waitForExistence(timeout: 10))
        app.terminate(); app.launch(); app.buttons["mappingJournal"].tap()
        XCTAssertEqual(records.count, 1); XCTAssertEqual(records.firstMatch.identifier, recordID)
        XCTAssertTrue(app.staticTexts["25"].exists); records.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["mappingRevisionBadge"].label.hasPrefix("Версия 3"))
        let originals = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "pointMeasurement-"))
        show(originals.firstMatch, app: app); XCTAssertEqual(originals.count, 1)
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "P33 effective point and preserved original"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.terminate(); app.launch(); app.buttons["selectHorizonPlan"].tap(); app.staticTexts["P2_PLAN_A.dxf"].tap()
        XCTAssertTrue(app.buttons["planPoints"].waitForExistence(timeout: 10)); XCTAssertTrue(app.buttons["planPoints"].label.contains("1"))
    }
    @MainActor private func disclosure(_ title: String, app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
    }
    // SwiftUI uppercases Section headers on this runtime; retain the full expected text/count.
    @MainActor private func heading(_ title: String, app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", title)).firstMatch
    }
    // SwiftUI vertical TextField uses TextView on iOS 17 and TextField on iOS 26.
    @MainActor private func multilineInput(_ identifier: String, app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier == %@ AND elementType IN %@", identifier,
            [XCUIElement.ElementType.textField.rawValue, XCUIElement.ElementType.textView.rawValue])).firstMatch
    }
    @MainActor private func fill(_ field: XCUIElement, _ text: String, app: XCUIApplication) {
        show(field, app: app)
        let old = field.value as? String ?? ""
        let placeholder = field.placeholderValue ?? ""
        field.tap()
        // Wait for actual keyboard readiness before sending events.
        let keyboard = app.keyboards.firstMatch
        if !keyboard.waitForExistence(timeout: 2) {
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).tap()
        }
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5), app.debugDescription)
        if !old.isEmpty && old != placeholder {
            for _ in old { field.typeText(XCUIKeyboardKey.delete.rawValue) }
        }
        // Keyboard batches can lose characters while validation or multiline rows update.
        // Separate native XCTest actions wait for quiescence after every character.
        for character in text { field.typeText(String(character)) }
        let actual = field.value as? String ?? ""
        XCTAssertEqual(actual == placeholder ? "" : actual, text, "Native keyboard input must reach the field intact")
        dismissKeyboard(app)
    }
    @MainActor private func show(_ element: XCUIElement, app: XCUIApplication, upward: Bool = true) {
        for _ in 0..<24 {
            if element.exists && element.isHittable {
                let centerY = element.frame.midY
                let navigationBottom = app.navigationBars.allElementsBoundByIndex.filter(\.isHittable).map { $0.frame.maxY }.max() ?? 0
                let tab = app.tabBars.firstMatch
                if centerY > navigationBottom && (!tab.exists || !tab.isHittable || centerY < tab.frame.minY) { return }
            }
            scrollForm(app, up: upward)
        }
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "Unreachable form element"; tree.lifetime = .keepAlways; add(tree)
        XCTFail("Element not visible: \(element)")
    }
    @MainActor func testP42DraftPhotosCancelDiscardTwoPointsAndRelaunch() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["FIELD_FORGE_TEST_RUN_ID"] = UUID().uuidString
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 30, height: 20))
        let images = [UIColor.red, .green, .blue].map { color in
            renderer.pngData { context in color.setFill(); context.fill(CGRect(x: 0, y: 0, width: 30, height: 20)) }.base64EncodedString()
        }
        app.launchEnvironment["P41_PHOTOS"] = String(data: try JSONEncoder().encode(images), encoding: .utf8)
        app.launchArguments = ["--ui-testing"]; app.launch()
        let project = "P42-\(UUID().uuidString.prefix(8))"
        create("projectPicker", name: project, app: app); select("projectPicker", value: project, app: app)
        create("horizonPicker", name: "+393 м", app: app); select("horizonPicker", value: "+393 м", app: app)
        create("excavationPicker", name: "E", app: app); select("excavationPicker", value: "E", app: app)
        reveal("draftPhotoCamera", app: app); app.buttons["draftPhotoCamera"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "в Simulator камеры нет")).firstMatch.waitForExistence(timeout: 5))
        app.buttons["Понятно"].tap()
        app.buttons["draftPhotoLibrary"].tap()
        let cancel = app.buttons.matching(NSPredicate(format: "label IN %@", ["Cancel", "Отмена", "Отменить"])).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 30)); cancel.tap()
        XCTAssertTrue(app.buttons["draftPhotoFiles"].waitForExistence(timeout: 5)); app.buttons["draftPhotoFiles"].tap()
        XCTAssertTrue(cancel.waitForExistence(timeout: 30)); cancel.tap()
        // Cancellation leaves no dirty draft; selecting the same context needs no discard.
        app.buttons["projectPicker"].tap(); app.buttons[project].tap()
        reveal("draftPhotoImportFixtures", app: app); app.buttons["draftPhotoImportFixtures"].tap()
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "draftPhoto-"))
        let imported = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == 3"), object: rows)
        XCTAssertEqual(XCTWaiter.wait(for: [imported], timeout: 20), .completed)
        let discardedIDs = rows.allElementsBoundByIndex.map(\.identifier)
        app.buttons["projectPicker"].tap(); app.buttons["Не выбрано"].tap()
        XCTAssertTrue(app.buttons["Остаться"].waitForExistence(timeout: 5)); app.buttons["Остаться"].tap()
        XCTAssertEqual(rows.count, 3)
        reveal("mappingDistance", app: app); app.buttons["mappingDistance"].tap()
        XCTAssertTrue(app.buttons["distanceDone"].waitForExistence(timeout: 10))
        app.buttons["distanceDone"].tap()
        XCTAssertEqual(rows.count, 3)
        app.buttons["projectPicker"].tap(); app.buttons["Не выбрано"].tap()
        app.buttons["Удалить черновик"].tap()
        select("projectPicker", value: project, app: app); select("horizonPicker", value: "+393 м", app: app); select("excavationPicker", value: "E", app: app)
        for point in ["5", "10"] {
            top(app); fill(app.textFields["mappingPicket"], point, app: app)
            fill(app.textFields["mappingZ"], "", app: app)
            reveal("draftPhotoImportFixtures", app: app); app.buttons["draftPhotoImportFixtures"].tap()
            let wait = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == 3"), object: rows)
            XCTAssertEqual(XCTWaiter.wait(for: [wait], timeout: 20), .completed)
            let ids = rows.allElementsBoundByIndex.map { $0.identifier.replacingOccurrences(of: "draftPhoto-", with: "photo-") }
            XCTAssertTrue(Set(rows.allElementsBoundByIndex.map(\.identifier)).isDisjoint(with: Set(discardedIDs)))
            let preview = rows.firstMatch; photoReveal(preview, app: app); preview.tap()
            XCTAssertTrue(app.buttons["draftPhotoClosePreview"].waitForExistence(timeout: 5)); app.buttons["draftPhotoClosePreview"].tap()
            top(app); app.buttons["selectHorizonPlan"].tap()
            XCTAssertTrue(app.buttons["Вернуться"].waitForExistence(timeout: 5)); app.buttons["Вернуться"].tap()
            // Form exposes offscreen rows lazily after returning at the top.
            photoReveal(rows.firstMatch, app: app)
            XCTAssertEqual(rows.count, 3)
            save(app); saved(app)
            top(app); XCTAssertTrue(app.buttons["projectPicker"].label.contains(project))
            XCTAssertTrue(app.buttons["horizonPicker"].label.contains("393")); XCTAssertTrue(app.buttons["excavationPicker"].label.contains("E"))
            XCTAssertEqual(app.textFields["mappingPicket"].value as? String, "Пикет: ПК 0+005 или метры")
            app.buttons["mappingJournal"].tap(); app.staticTexts[point].tap()
            photoReveal(app.buttons["photoCamera"], app: app)
            let savedRows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "photo-"))
            XCTAssertEqual(Set(savedRows.allElementsBoundByIndex.map(\.identifier)), Set(ids))
            savedRows.firstMatch.tap()
            photoReveal(app.staticTexts["Место съёмки неизвестно · фото черновика"], app: app)
            XCTAssertTrue(app.staticTexts["Место съёмки неизвестно · фото черновика"].exists)
            app.buttons["photoCloseDetail"].tap()
            app.terminate(); app.launch()
            app.buttons["mappingJournal"].tap(); app.staticTexts[point].tap()
            photoReveal(app.buttons["photoCamera"], app: app)
            XCTAssertEqual(Set(savedRows.allElementsBoundByIndex.map(\.identifier)), Set(ids))
            app.terminate(); app.launch()
        }
        let other = "Other-\(UUID().uuidString.prefix(8))"
        create("projectPicker", name: other, app: app); select("projectPicker", value: other, app: app)
        app.buttons["mappingJournal"].tap(); XCTAssertTrue(app.staticTexts["journalEmpty"].waitForExistence(timeout: 5))
    }
    @MainActor func testP41ThreePhotosMetadataZoomCameraUnavailableAndRelaunch() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["FIELD_FORGE_TEST_RUN_ID"] = UUID().uuidString
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 30, height: 20))
        let images = [UIColor.red, .green, .blue].map { color in
            renderer.pngData { context in color.setFill(); context.fill(CGRect(x: 0, y: 0, width: 30, height: 20)) }.base64EncodedString()
        }
        app.launchEnvironment["P41_PHOTOS"] = String(data: try JSONEncoder().encode(images), encoding: .utf8)
        app.launchArguments = ["--ui-testing"]; app.launch()
        let project = "P41-\(UUID().uuidString.prefix(8))"
        create("projectPicker", name: project, app: app); select("projectPicker", value: project, app: app)
        create("horizonPicker", name: "+393 м", app: app); select("horizonPicker", value: "+393 м", app: app)
        create("excavationPicker", name: "E", app: app); select("excavationPicker", value: "E", app: app)
        top(app); fill(app.textFields["mappingPicket"], "5", app: app)
        fill(app.textFields["mappingZ"], "", app: app); save(app); saved(app)
        app.buttons["mappingJournal"].tap(); app.staticTexts["5"].tap()
        photoReveal(app.buttons["photoCamera"], app: app); app.buttons["photoCamera"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "в Simulator камеры нет")).firstMatch.waitForExistence(timeout: 5))
        app.buttons["Понятно"].tap()
        app.buttons["photoLibrary"].tap()
        // Exercise actual system Photos picker cancellation; no broad library permission requested.
        let cancel = app.buttons.matching(NSPredicate(format: "label IN %@", ["Cancel", "Отмена"])).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 30)); cancel.tap()
        XCTAssertTrue(app.buttons["photoImportFixtures"].waitForExistence(timeout: 5)); photoReveal(app.buttons["photoImportFixtures"], app: app); app.buttons["photoImportFixtures"].tap()
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "photo-"))
        let imported = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == 3"), object: rows)
        XCTAssertEqual(XCTWaiter.wait(for: [imported], timeout: 20), .completed)
        var ids: [String] = []
        for index in 0..<3 {
            let row = rows.element(boundBy: index); ids.append(row.identifier); photoReveal(row, app: app); row.tap()
            XCTAssertTrue(app.textFields["photoName"].waitForExistence(timeout: 5))
            fill(app.textFields["photoName"], "Фото \(index + 1)", app: app)
            fill(app.textFields["photoNumber"], String(index + 1), app: app)
            fill(app.textFields["photoCorrectionReason"], "Уточнение названия", app: app)
            photoReveal(app.buttons["photoSaveMetadata"], app: app); app.buttons["photoSaveMetadata"].tap()
            XCTAssertTrue(app.staticTexts["photoCaptureTime"].label.contains("неизвестно"))
            photoReveal(app.buttons["photoOpenFullScreen"], app: app, upward: false); app.buttons["photoOpenFullScreen"].tap()
            XCTAssertTrue(app.scrollViews["photoZoomView"].waitForExistence(timeout: 10))
            app.scrollViews["photoZoomView"].pinch(withScale: 2, velocity: 1)
            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screenshot.name = "P41 photo \(index + 1) zoom"; screenshot.lifetime = .keepAlways; add(screenshot)
            app.buttons["photoCloseFullScreen"].tap(); app.buttons["photoCloseDetail"].tap()
        }
        XCTAssertEqual(Set(ids).count, 3)
        app.terminate(); app.launch(); app.buttons["mappingJournal"].tap(); app.staticTexts["5"].tap()
        photoReveal(app.buttons["photoCamera"], app: app)
        XCTAssertEqual(rows.count, 3)
        for index in 0..<3 { XCTAssertTrue(rows.element(boundBy: index).label.contains("Фото \(index + 1)")) }
        // Adding/correcting photos does not create a geological revision.
        photoReveal(app.buttons["editMappingObservation"], app: app, upward: false)
        XCTAssertTrue(app.staticTexts["Версия 1 · исходное наблюдение"].exists)
    }
    @MainActor private func photoReveal(_ element: XCUIElement, app: XCUIApplication, upward: Bool = true) {
        for _ in 0..<24 {
            let form = activeForm(app)
            if element.exists && element.isHittable {
                let center = CGPoint(x: element.frame.midX, y: element.frame.midY)
                let tab = app.tabBars.firstMatch
                let navigationBottom = app.navigationBars.allElementsBoundByIndex.filter(\.isHittable).map { $0.frame.maxY }.max() ?? 0
                if form.frame.contains(center), center.y > navigationBottom,
                   !tab.exists || !tab.isHittable || center.y < tab.frame.minY { return }
            }
            scrollForm(app, up: upward)
        }
        XCTAssertTrue(element.isHittable)
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
        let form = activeForm(app)
        let frame = form.frame
        let navigationBottom = app.navigationBars.allElementsBoundByIndex.filter(\.isHittable).map { $0.frame.maxY }.max() ?? 0
        let tab = app.tabBars.firstMatch
        let top = max(frame.minY, navigationBottom) + 12
        let bottom = min(frame.maxY, tab.exists && tab.isHittable ? tab.frame.minY : frame.maxY) - 24
        let height = max(40, bottom - top)
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: frame.minX + frame.width * 0.05, dy: top + height * (up ? 0.75 : 0.25)))
        let end = origin.withOffset(CGVector(dx: frame.minX + frame.width * 0.05, dy: top + height * (up ? 0.25 : 0.75)))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
    }
    @MainActor private func activeForm(_ app: XCUIApplication) -> XCUIElement {
        app.collectionViews.allElementsBoundByIndex.last(where: \.isHittable) ?? app.collectionViews.firstMatch
    }
    @MainActor private func create(_ picker: String, name: String, app: XCUIApplication) {
        let button = app.buttons["manage-\(picker)"]; XCTAssertTrue(button.waitForExistence(timeout: 10)); button.tap()
        let field = app.textFields[picker == "horizonPicker" ? "contextElevation" : "contextName"]; XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText(picker == "horizonPicker" ? "393" : name)
        dismissKeyboard(app)
        app.buttons["saveContext"].tap()
        if picker == "horizonPicker" { app.buttons["Закрыть"].tap() }
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: button)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
    }
    @MainActor private func select(_ picker: String, value: String, app: XCUIApplication) {
        app.buttons[picker].tap(); app.buttons[value].tap()
    }
    @MainActor private func dismissKeyboard(_ app: XCUIApplication) { if app.buttons["Готово"].exists { app.buttons["Готово"].tap() } }
    @MainActor private func save(_ app: XCUIApplication) {
        let button = app.buttons["saveMappingObservation"]
        // A partially exposed Form row can report hittable while its center is under the tab bar.
        // Scroll the tap point into the form before tapping; do not mistake a tab tap for a save.
        for _ in 0..<24 {
            if button.exists && button.isHittable && app.collectionViews.firstMatch.frame.contains(
                CGPoint(x: button.frame.midX, y: button.frame.midY)) && button.frame.midY < app.tabBars.firstMatch.frame.minY { break }
            scrollForm(app, up: true)
        }
        XCTAssertTrue(button.isHittable)
        XCTAssertTrue(app.collectionViews.firstMatch.frame.contains(CGPoint(x: button.frame.midX, y: button.frame.midY)))
        XCTAssertLessThan(button.frame.midY, app.tabBars.firstMatch.frame.minY)
        button.tap()
    }
    @MainActor private func saved(_ app: XCUIApplication) {
        XCTAssertTrue(app.alerts["Наблюдение сохранено"].waitForExistence(timeout: 5), app.debugDescription); app.buttons["Продолжить"].tap()
    }
}
