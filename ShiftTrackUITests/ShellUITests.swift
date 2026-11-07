import XCTest

/// Taps the simulator. This file does not run on the Linux agent.
final class ShellUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testWeekMoveTimeSheetAndTabsLeaveStoredDatesAlone() throws {
        let app = XCUIApplication()
        app.launch()

        let today = app.buttons["tab.today"]
        XCTAssertTrue(today.waitForExistence(timeout: 12))
        let clock = app.staticTexts["today.clock"]
        XCTAssertTrue(clock.waitForExistence(timeout: 8))
        let clockBefore = clock.label
        shot("01-today")

        app.buttons["today.week.next"].tap()
        XCTAssertEqual(clock.label, clockBefore)
        app.otherElements["today.week"].swipeRight()
        XCTAssertEqual(clock.label, clockBefore)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "いま稼いだお給料")).firstMatch.exists)

        app.buttons["tab.calendar"].tap()
        shot("02-calendar")
        app.buttons["calendar.nextMonth"].tap()
        let back = app.buttons["calendar.thisMonth"]
        XCTAssertTrue(back.waitForExistence(timeout: 4))
        back.tap()
        XCTAssertFalse(back.exists)

        app.buttons["tab.workplaces"].tap()
        shot("03-workplaces-empty")
        app.buttons["勤務先を追加"].tap()
        let name = app.textFields["field.名前"]
        XCTAssertTrue(name.waitForExistence(timeout: 6))
        name.tap()
        name.typeText("店")
        if app.keyboards.buttons["完了"].exists {
            app.keyboards.buttons["完了"].tap()
        } else if app.buttons["完了"].exists {
            app.buttons["完了"].tap()
        }
        app.swipeUp()
        app.buttons["完了する"].tap()
        let card = app.buttons["workplace.card"]
        XCTAssertTrue(card.waitForExistence(timeout: 6))
        card.tap()
        XCTAssertTrue(app.navigationBars["パターン"].waitForExistence(timeout: 6))
        shot("04-patterns")
        app.buttons["patterns.close"].tap()

        app.buttons["tab.today"].tap()
        XCTAssertEqual(clock.label, clockBefore)
        app.buttons["＋シフトを追加"].tap()
        app.buttons["1件ずつ入力"].tap()
        app.buttons["開始"].tap()
        XCTAssertTrue(app.navigationBars["開始の時刻"].waitForExistence(timeout: 6))
        app.buttons["1時間後"].tap()
        shot("05-time")
        app.buttons["キャンセル"].tap()
        XCTAssertFalse(app.navigationBars["開始の時刻"].exists)

        app.buttons["tab.income"].tap()
        shot("06-income")
        app.buttons["income.walls"].tap()
        XCTAssertTrue(app.staticTexts["walls.title"].waitForExistence(timeout: 6))
        shot("07-walls")

        app.buttons["tab.settings"].tap()
        shot("08-settings")
        XCTAssertFalse(app.staticTexts["勤務先の設定"].exists)
        XCTAssertEqual(clock.label, clockBefore)
    }

    private func shot(_ name: String) {
        let image = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let directory = URL(fileURLWithPath: "/tmp/shifttrack-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? image.pngRepresentation.write(to: directory.appendingPathComponent("\(name).png"))
    }
}
