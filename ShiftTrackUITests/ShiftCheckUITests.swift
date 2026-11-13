import XCTest

/// The confirmation sheet edits the actual clocks and leaves the planned shift.
/// Fictional workplace only: 架空茶房 北窓.
final class ShiftCheckUITests: XCTestCase {
    func testActualTimesAdjustOnTheConfirmationSheet() throws {
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            throw XCTSkip("The confirmation sheet is opened from the iPhone home tab.")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-UITestingSample", "-UITestingConfirm"]
        app.launch()
        XCTAssertTrue(app.tab("ホーム").waitForExistence(timeout: 15))
        if app.buttons["閉じる"].waitForExistence(timeout: 2) {
            app.buttons["閉じる"].tap()
        }

        let row = app.buttons["today.unconfirmed"]
        for _ in 0..<8 where !row.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(row.waitForExistence(timeout: 4))
        row.tap()

        let cafe = app.descendants(matching: .any)["check.open"]
        XCTAssertTrue(cafe.waitForExistence(timeout: 8))
        XCTAssertTrue(cafe.label.contains("架空茶房 北窓"))
        cafe.tap()
        XCTAssertTrue(app.navigationBars["勤務の確認"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["時間を直す"].exists)
        XCTAssertTrue(app.buttons["check.edit"].waitForExistence(timeout: 4))

        let worked = app.descendants(matching: .any)["check.worked"]
        let yen = app.descendants(matching: .any)["check.yen"]
        XCTAssertTrue(worked.waitForExistence(timeout: 4))
        let beforeWorked = worked.label
        let beforeYen = yen.label
        XCTAssertTrue(beforeWorked.contains("4時間30分"))
        XCTAssertFalse(app.staticTexts["check.changed.開始"].exists)

        app.buttons["check.start"].tap()
        let later = app.buttons["check.start.plus15"]
        XCTAssertTrue(later.waitForExistence(timeout: 4))
        later.tap()

        let changed = app.staticTexts["check.changed.開始"]
        XCTAssertTrue(changed.waitForExistence(timeout: 4))
        XCTAssertTrue(changed.label.contains("10:00"))
        XCTAssertTrue(worked.label.contains("4時間15分"))
        XCTAssertNotEqual(yen.label, beforeYen)

        app.buttons["check.confirm"].tap()
        XCTAssertTrue(app.staticTexts["確認していない勤務はありません"].waitForExistence(timeout: 8))
    }
}
