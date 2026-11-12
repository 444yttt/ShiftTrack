import XCTest

/// Dark-appearance shots of the main screens, using the fictional 架空茶房 北窓.
final class DarkShotUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.appearance = .dark
    }

    override func tearDownWithError() throws {
        XCUIDevice.shared.appearance = .light
    }

    func testDarkScreens() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestingSample", "-UITestingDark"]
        app.launch()

        XCTAssertTrue(app.tab("ホーム").waitForExistence(timeout: 15))
        if app.buttons["閉じる"].waitForExistence(timeout: 2) {
            app.buttons["閉じる"].tap()
        }
        show(app.staticTexts["架空茶房 北窓"])
        XCTAssertTrue(app.staticTexts["today.earned"].waitForExistence(timeout: 8))
        shot(app, "dark-home")

        app.buttons["today.add"].tap()
        let editor = app.navigationBars["シフトを追加"]
        XCTAssertTrue(editor.waitForExistence(timeout: 6))
        shot(app, "dark-add-shift")
        editor.buttons["キャンセル"].tap()

        app.tab("カレンダー").tap()
        show(app.buttons["calendar.nextMonth"])
        shot(app, "dark-calendar")

        app.tab("設定").tap()
        if app.buttons["おわり"].waitForExistence(timeout: 2) {
            app.buttons["おわり"].tap()
        }
        show(app.buttons["settings.messages"])
        shot(app, "dark-settings")

        app.tab("勤務先").tap()
        show(app.buttons["workplace.add"])
        shot(app, "dark-workplaces")

        show(app.buttons["workplace.edit.架空茶房 北窓"])
        app.buttons["workplace.edit.架空茶房 北窓"].tap()
        let workplaceEditor = app.navigationBars["勤務先を編集"]
        XCTAssertTrue(workplaceEditor.waitForExistence(timeout: 6))
        shot(app, "dark-workplace-edit")
        workplaceEditor.buttons["キャンセル"].tap()

        show(app.buttons["workplace.card"])
        app.buttons["workplace.card"].tap()
        show(app.buttons["workplace.pattern.add"])
        app.buttons["workplace.pattern.add"].tap()
        let patternEditor = app.navigationBars["パターンを作る"]
        XCTAssertTrue(patternEditor.waitForExistence(timeout: 6))
        shot(app, "dark-pattern-editor")
    }

    private func show(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 8), file: file, line: line)
        if element.isHittable { return }
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: element)
        wait(for: [ready], timeout: 8)
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let image = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let directory = URL(fileURLWithPath: "/tmp/shifttrack-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? image.pngRepresentation.write(to: directory.appendingPathComponent("after-\(name).png"))
    }
}
