import XCTest

/// Taps the simulator. This file does not run on the Linux agent.
final class ShellUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testWeekMoveTimeSheetAndTabsLeaveStoredDatesAlone() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestingReset"]
        app.launch()

        let today = app.tab("ホーム")
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

        app.tab("カレンダー").tap()
        shot("02-calendar")
        app.buttons["calendar.nextMonth"].tap()
        let back = app.buttons["calendar.thisMonth"]
        XCTAssertTrue(back.waitForExistence(timeout: 4))
        back.tap()
        XCTAssertFalse(back.exists)

        app.tab("勤務先").tap()
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
        // The wizard: お店 → 時給と給料日 (the default wage is filled in) → よく入る時間.
        app.buttons["wizard.next"].tap()
        app.buttons["wizard.next"].tap()
        app.buttons["wizard.finish"].tap()
        let card = app.buttons.matching(identifier: "workplace.card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 6))
        let saveButton = app.buttons["完了する"]
        if saveButton.exists {
            let gone = NSPredicate(format: "exists == false")
            expectation(for: gone, evaluatedWith: saveButton, handler: nil)
            waitForExpectations(timeout: 4)
        }
        card.tap()
        let heading = app.staticTexts["patterns.heading"]
        if !heading.waitForExistence(timeout: 4), card.isHittable {
            card.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).tap()
        }
        require(heading, timeout: 6, shotName: "04-patterns-missing", app: app)
        shot("04-patterns")
        app.buttons["patterns.close"].tap()

        app.tab("ホーム").tap()
        XCTAssertEqual(clock.label, clockBefore)
        app.buttons["＋シフトを追加"].tap()
        let start = app.buttons["開始"]
        require(start, timeout: 8, shotName: "05-editor-missing", app: app)
        start.tap()
        let timeBar = app.navigationBars["開始の時刻"]
        require(timeBar, timeout: 6, shotName: "05-time-missing", app: app)
        app.buttons["1時間後"].tap()
        shot("05-time")
        let cancel = app.buttons["time.cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 4))
        cancel.tap()
        if !waitUntilGone(timeBar, timeout: 8), cancel.exists {
            cancel.tap()
        }
        XCTAssertTrue(waitUntilGone(timeBar, timeout: 8))
        let editorBar = app.navigationBars["シフトを追加"]
        if editorBar.waitForExistence(timeout: 2) {
            editorBar.buttons["キャンセル"].tap()
        }

        app.tab("給料").tap()
        shot("06-income")
        let walls = app.buttons["income.walls"]
        XCTAssertTrue(walls.waitForExistence(timeout: 6))
        tapVisible(app, walls)
        require(app.staticTexts["walls.title"], timeout: 6, shotName: "07-walls-missing", app: app)
        shot("07-walls")
        app.buttons["walls.close"].tap()

        app.tab("設定").tap()
        shot("08-settings")
        XCTAssertFalse(app.staticTexts["勤務先の設定"].exists)
        XCTAssertFalse(app.otherElements["guide.card"].exists)
        let messages = app.buttons["settings.messages"]
        XCTAssertTrue(messages.waitForExistence(timeout: 6))
        tapVisible(app, messages)
        let messageTitle = app.navigationBars["連絡メッセージのひな形"]
        XCTAssertTrue(messageTitle.waitForExistence(timeout: 6))
        app.buttons["閉じる"].tap()
        XCTAssertTrue(app.switches["settings.notifyEnd"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.switches["settings.notifyBefore"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["settings.location"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.switches["settings.calendar"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.switches["settings.reminders"].waitForExistence(timeout: 4))
        app.tab("ホーム").tap()
        XCTAssertEqual(clock.label, clockBefore)
    }

    private func waitUntilGone(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let gone = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: gone, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func tapVisible(_ app: XCUIApplication, _ element: XCUIElement) {
        let top: CGFloat = 90
        let bottom = app.frame.maxY - 120
        for _ in 0..<8 {
            let frame = element.frame
            if element.isHittable && frame.minY > top && frame.maxY < bottom {
                element.tap()
                return
            }
            if frame.minY < top {
                app.swipeDown()
            } else {
                app.swipeUp()
            }
        }
        element.tap()
    }

    private func require(_ element: XCUIElement, timeout: TimeInterval, shotName: String, app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        if element.waitForExistence(timeout: timeout) { return }
        shot(shotName)
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = "hierarchy-\(shotName)"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTFail("画面に出ませんでした: \(shotName)", file: file, line: line)
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
