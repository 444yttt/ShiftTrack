import XCTest

/// Taps the day chip and the calendar pattern row. Linux does not run this.
final class PatternPlaceUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testPatternRowAndDayChipPlaceSkipAndHold() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestingReset"]
        app.launch()

        let today = app.buttons["tab.today"]
        XCTAssertTrue(today.waitForExistence(timeout: 12))
        let clock = app.staticTexts["today.clock"]
        XCTAssertTrue(clock.waitForExistence(timeout: 8))
        let clockBefore = clock.label

        app.buttons["tab.workplaces"].tap()
        app.buttons["勤務先を追加"].tap()
        let name = app.textFields["field.名前"]
        XCTAssertTrue(name.waitForExistence(timeout: 6))
        name.tap()
        name.typeText("店")
        dismissKeyboard(app)
        app.swipeUp()
        app.buttons["追加して次へ"].tap()
        app.buttons["次へ"].tap()
        app.buttons["はじめる"].tap()
        XCTAssertTrue(app.buttons["workplace.card"].waitForExistence(timeout: 6))

        app.buttons["tab.calendar"].tap()
        shot("10-calendar-before-part")
        let days = monthDays(app)
        XCTAssertGreaterThanOrEqual(days.count, 3)
        revealGrid(app)
        tapVisible(app, days[0])

        makePart(app, named: "朝", startHoursAfter10: 0, endHoursAfter15: 0, todo: "レジ")
        tapIdentifier(app, "calendar.pattern.朝")
        let result = app.staticTexts["pattern.result"]
        XCTAssertTrue(result.waitForExistence(timeout: 4))
        XCTAssertTrue(result.label.contains("置いた件数 1"))
        let shift = app.buttons["calendar.shift"]
        XCTAssertTrue(shift.waitForExistence(timeout: 4))
        let todo = app.staticTexts["shift.todos"]
        XCTAssertTrue(todo.waitForExistence(timeout: 4) || shift.label.contains("レジ"))
        XCTAssertFalse(shift.label.contains("休憩"))
        shot("11-placed")

        tapIdentifier(app, "calendar.pattern.朝")
        XCTAssertTrue(result.label.contains("置いた件数 0"))
        XCTAssertEqual(app.buttons.matching(identifier: "calendar.shift").count, 1)
        shot("12-same-part-skip")

        makePart(app, named: "別", startHoursAfter10: 0, endHoursAfter15: 0, todo: "")
        tapIdentifier(app, "calendar.pick.mode")
        revealGrid(app)
        tapVisible(app, days[0])
        tapVisible(app, days[1])
        let picked = app.staticTexts["calendar.picked.count"]
        XCTAssertTrue(picked.waitForExistence(timeout: 3))
        XCTAssertTrue(picked.label.contains("2"))
        tapIdentifier(app, "calendar.pattern.別")
        let pending = app.otherElements["pattern.pending"]
        let pendingText = app.staticTexts["pattern.pending"]
        XCTAssertTrue(pending.waitForExistence(timeout: 4) || pendingText.waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["のシフトがあります"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "確認が必要な日があります")).firstMatch.exists)
        tapIdentifier(app, "calendar.pick.mode")
        revealGrid(app)
        tapVisible(app, days[1])
        XCTAssertFalse(app.buttons["calendar.shift"].exists)
        shot("13-clash-pending")
        tapIdentifier(app, "pattern.pending.close")

        tapVisible(app, days[1])
        tapIdentifier(app, "calendar.daychip.別")
        XCTAssertTrue(result.label.contains("置いた件数 1"))
        XCTAssertTrue(app.buttons["calendar.shift"].waitForExistence(timeout: 4))
        shot("14-daychip")

        makePart(app, named: "夜", startHoursAfter10: 12, endHoursAfter15: 14, todo: "")
        revealGrid(app)
        tapVisible(app, days[2])
        tapIdentifier(app, "calendar.pattern.夜")
        XCTAssertTrue(result.label.contains("置いた件数 1"))
        let overnight = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "22:00")).firstMatch
        XCTAssertTrue(overnight.waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "5:00")).firstMatch.exists)
        shot("15-overnight")

        revealGrid(app)
        tapVisible(app, days[0])
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "10:00")).firstMatch.waitForExistence(timeout: 4))
        XCTAssertEqual(app.buttons.matching(identifier: "calendar.shift").count, 1)

        app.buttons["tab.today"].tap()
        XCTAssertEqual(clock.label, clockBefore)
        tapIdentifier(app, "today.daychip.朝")
        shot("16-today-daychip")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "いま稼いだお給料")).firstMatch.exists)
        app.buttons["today.week.next"].tap()
        XCTAssertEqual(clock.label, clockBefore)
        shot("17-week-still")
    }

    private func monthDays(_ app: XCUIApplication) -> [XCUIElement] {
        let query = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'calendar.day.'"))
        XCTAssertTrue(query.firstMatch.waitForExistence(timeout: 6))
        var days: [XCUIElement] = []
        for index in 0..<query.count {
            let element = query.element(boundBy: index)
            if element.identifier == "calendar.day.today" { continue }
            days.append(element)
        }
        return days
    }

    private func makePart(
        _ app: XCUIApplication,
        named name: String,
        startHoursAfter10: Int,
        endHoursAfter15: Int,
        todo: String
    ) {
        tapIdentifier(app, "calendar.part.add")
        let field = app.textFields["field.パターン名"]
        XCTAssertTrue(field.waitForExistence(timeout: 6))
        field.tap()
        field.typeText(name)
        if !todo.isEmpty {
            let todoField = app.textFields["field.やること"].exists
                ? app.textFields["field.やること"]
                : app.textViews["field.やること"]
            XCTAssertTrue(todoField.waitForExistence(timeout: 4))
            todoField.tap()
            todoField.typeText(todo)
        }
        dismissKeyboard(app)
        if startHoursAfter10 > 0 {
            nudge(app, title: "開始", times: startHoursAfter10)
        }
        if endHoursAfter15 > 0 {
            nudge(app, title: "終了", times: endHoursAfter15)
        }
        app.buttons["pattern.save"].tap()
        XCTAssertTrue(app.buttons["calendar.pattern.\(name)"].waitForExistence(timeout: 6))
    }

    private func nudge(_ app: XCUIApplication, title: String, times: Int) {
        let opener = app.buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch
        XCTAssertTrue(opener.waitForExistence(timeout: 4))
        opener.tap()
        let bar = app.navigationBars["\(title)の時刻"]
        XCTAssertTrue(bar.waitForExistence(timeout: 4))
        let step = app.buttons["1時間後"]
        XCTAssertTrue(step.waitForExistence(timeout: 4))
        for _ in 0..<times {
            step.tap()
        }
        app.buttons["決定"].tap()
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: bar, handler: nil)
        waitForExpectations(timeout: 4)
    }

    private func tapIdentifier(_ app: XCUIApplication, _ identifier: String) {
        let element = app.buttons[identifier]
        XCTAssertTrue(element.waitForExistence(timeout: 6), identifier)
        tapVisible(app, element)
    }

    /// A control under the tab bar still reports hittable, and the tap lands
    /// on the bar. Keep the frame in the open part of the screen.
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

    private func revealGrid(_ app: XCUIApplication) {
        for _ in 0..<4 {
            app.swipeDown()
        }
    }

    private func dismissKeyboard(_ app: XCUIApplication) {
        if app.keyboards.buttons["完了"].exists {
            app.keyboards.buttons["完了"].tap()
        } else if app.buttons["完了"].exists {
            app.buttons["完了"].tap()
        }
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
