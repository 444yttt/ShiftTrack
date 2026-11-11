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
        shot(app, "today")
        XCTAssertTrue(app.staticTexts["架空茶房 北窓"].waitForExistence(timeout: 6))

        app.buttons["tab.calendar"].tap()
        shot(app, "calendar")
        XCTAssertTrue(app.buttons["calendar.nextMonth"].waitForExistence(timeout: 4))

        app.buttons["tab.workplaces"].tap()
        shot(app, "workplaces")

        app.buttons["tab.settings"].tap()
        if app.buttons["おわり"].waitForExistence(timeout: 2) {
            shot(app, "settings-guide")
            app.buttons["おわり"].tap()
        }
        shot(app, "settings")
        XCTAssertTrue(app.buttons["settings.messages"].waitForExistence(timeout: 4))
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
