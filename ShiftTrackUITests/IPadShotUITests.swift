import XCTest

/// Regular-width shots in both orientations. Skipped on iPhone, where the
/// tab bar and full-width column stay as they are.
final class IPadShotUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad layout shots run on an iPad simulator")
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws {
        XCUIDevice.shared.orientation = .portrait
    }

    func testRegularWidthPortraitAndLandscape() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestingSample"]
        app.launch()

        revealSidebar(app)
        XCTAssertTrue(tab(app, "ホーム").waitForExistence(timeout: 15))
        if app.buttons["閉じる"].waitForExistence(timeout: 2) {
            app.buttons["閉じる"].tap()
        }
        XCTAssertTrue(app.staticTexts["架空茶房 北窓"].waitForExistence(timeout: 8))
        shot(app, "ipad-portrait-home")

        open(app, "カレンダー")
        XCTAssertTrue(app.buttons["calendar.nextMonth"].waitForExistence(timeout: 8))
        shot(app, "ipad-portrait-calendar")

        open(app, "設定")
        XCTAssertTrue(app.staticTexts["設定"].waitForExistence(timeout: 8))
        shot(app, "ipad-portrait-settings")

        open(app, "勤務先")
        XCTAssertTrue(app.buttons["workplace.edit.架空茶房 北窓"].waitForExistence(timeout: 8))
        shot(app, "ipad-portrait-workplaces")

        XCUIDevice.shared.orientation = .landscapeLeft
        open(app, "ホーム")
        XCTAssertTrue(app.staticTexts["架空茶房 北窓"].waitForExistence(timeout: 8))
        shot(app, "ipad-landscape-home")

        app.buttons["today.add"].tap()
        XCTAssertTrue(app.navigationBars["シフトを追加"].waitForExistence(timeout: 8))
        shot(app, "ipad-landscape-shift-editor")
        app.navigationBars["シフトを追加"].buttons["キャンセル"].tap()

        open(app, "カレンダー")
        shot(app, "ipad-landscape-calendar")
        open(app, "設定")
        shot(app, "ipad-landscape-settings")
    }

    private func tab(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        // The identifier lands on the row and on its label, so a subscript query
        // matches more than one element. The first button is the row.
        app.buttons.matching(identifier: "pad.tab.\(title)").firstMatch
    }

    private func revealSidebar(_ app: XCUIApplication) {
        let row = tab(app, "ホーム")
        if row.waitForExistence(timeout: 4), row.isHittable { return }
        let toggle = app.buttons["pad.sidebar"]
        if toggle.waitForExistence(timeout: 4) {
            toggle.tap()
        }
    }

    private func open(_ app: XCUIApplication, _ title: String) {
        let row = tab(app, title)
        if row.waitForExistence(timeout: 4), row.isHittable {
            row.tap()
            return
        }
        let toggle = app.buttons["pad.sidebar"]
        if toggle.waitForExistence(timeout: 2) {
            toggle.tap()
        }
        XCTAssertTrue(row.waitForExistence(timeout: 4))
        row.tap()
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
