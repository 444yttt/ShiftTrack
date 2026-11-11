import XCTest

/// Screenshots of the current build with a fictional workplace.
final class SampleShotUITests: XCTestCase {
    func testFictionalWorkplaceScreens() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestingSample"]
        app.launch()
        XCTAssertTrue(app.buttons["tab.today"].waitForExistence(timeout: 15))
        dismissGuide(app, name: "today-guide")
        shot(app, "today")
        XCTAssertTrue(app.staticTexts["架空茶房 北窓"].waitForExistence(timeout: 6))

        app.buttons["tab.calendar"].tap()
        dismissGuide(app, name: "calendar-guide")
        shot(app, "calendar")

        app.buttons["tab.workplaces"].tap()
        dismissGuide(app, name: "workplaces-guide")
        shot(app, "workplaces")

        app.buttons["tab.settings"].tap()
        dismissGuide(app, name: "settings-guide")
        shot(app, "settings")
    }

    private func dismissGuide(_ app: XCUIApplication, name: String) {
        let card = app.descendants(matching: .any)["guide.card"]
        guard card.waitForExistence(timeout: 4) else { return }
        shot(app, name)
        let close = app.buttons["閉じる"]
        if close.waitForExistence(timeout: 2) {
            close.tap()
        }
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let image = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: image)
        attachment.name = "before-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
        let directory = URL(fileURLWithPath: "/tmp/shifttrack-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? image.pngRepresentation.write(to: directory.appendingPathComponent("before-\(name).png"))
    }
}
