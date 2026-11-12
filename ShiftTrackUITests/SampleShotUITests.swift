import XCTest

/// Screenshots of the fictional workplace. This file does not run on the Linux agent.
final class SampleShotUITests: XCTestCase {
    func testFictionalWorkplaceScreens() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestingSample"]
        app.launch()
        XCTAssertTrue(app.buttons["tab.today"].waitForExistence(timeout: 15))
        if app.buttons["閉じる"].waitForExistence(timeout: 2) {
            shot(app, "guide")
            app.buttons["閉じる"].tap()
        }
        let name = app.staticTexts["架空茶房 北窓"]
        show(name)
        // The sample shift is running, so the live earnings and the clock are on screen.
        XCTAssertTrue(app.staticTexts["today.earned"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["today.time"].exists)
        shot(app, "today")
        app.swipeUp()
        shot(app, "today-actions")
        // No phone number in the sample: 電話 and メッセージ are disabled and say why.
        XCTAssertFalse(app.buttons["today.action.phone"].isEnabled)
        XCTAssertTrue(app.buttons["today.action.map"].isEnabled)
        app.swipeDown()
        app.swipeDown()

        app.buttons["＋シフトを追加"].tap()
        let editor = app.navigationBars["シフトを追加"]
        XCTAssertTrue(editor.waitForExistence(timeout: 6))
        shot(app, "add-shift")
        editor.buttons["キャンセル"].tap()

        app.buttons["tab.calendar"].tap()
        show(app.buttons["calendar.nextMonth"])
        shot(app, "calendar")

        app.buttons["tab.workplaces"].tap()
        show(app.buttons["workplace.add"])
        shot(app, "workplaces")
        show(app.buttons["workplace.card"])
        app.buttons["workplace.card"].tap()
        show(app.buttons["workplace.pattern.add"])
        app.buttons["workplace.pattern.add"].tap()
        let patternEditor = app.navigationBars["パターンを作る"]
        XCTAssertTrue(patternEditor.waitForExistence(timeout: 6))
        shot(app, "pattern-editor")
        app.buttons["pattern.editor.close"].tap()

        app.buttons["tab.settings"].tap()
        if app.buttons["おわり"].waitForExistence(timeout: 2) {
            shot(app, "settings-guide")
            app.buttons["おわり"].tap()
        }
        show(app.buttons["settings.messages"])
        shot(app, "settings")
        var reminders = app.switches["settings.reminders"]
        for _ in 0..<4 where !reminders.isHittable {
            app.swipeUp()
            reminders = app.switches["settings.reminders"]
        }
        show(reminders)
        shot(app, "settings-permissions")
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
