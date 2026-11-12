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
        app.launchArguments = ["-UITestingSample"]
        app.launch()

        let home = app.staticTexts["today.greeting"]
        XCTAssertTrue(home.waitForExistence(timeout: 8))
        shot(app, "dark-home")

        app.tab("カレンダー").tap()
        XCTAssertTrue(app.navigationBars["カレンダー"].waitForExistence(timeout: 5))
        shot(app, "dark-calendar")

        app.tab("ホーム").tap()
        app.buttons["today.add"].tap()
        XCTAssertTrue(app.navigationBars["シフトを追加"].waitForExistence(timeout: 5))
        shot(app, "dark-add-shift")
        app.buttons["キャンセル"].tap()

        app.tab("設定").tap()
        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 5))
        shot(app, "dark-settings")

        app.tab("勤務先").tap()
        XCTAssertTrue(app.staticTexts["架空茶房 北窓"].waitForExistence(timeout: 5))
        shot(app, "dark-workplaces")

        app.buttons["workplace.edit.架空茶房 北窓"].tap()
        XCTAssertTrue(app.navigationBars["勤務先を編集"].waitForExistence(timeout: 5))
        shot(app, "dark-workplace-edit")
        app.buttons["キャンセル"].tap()

        show(app.buttons["workplace.pattern.add"])
        app.buttons["workplace.pattern.add"].tap()
        XCTAssertTrue(app.navigationBars["パターンを作る"].waitForExistence(timeout: 5))
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
