import XCTest

/// Pattern edit, undo and delete from the calendar. Runs on macOS CI only.
final class PatternEditUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testPlaceUndoRenameAndDeleteAPattern() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestingReset"]
        app.launch()

        XCTAssertTrue(app.tab("勤務先").waitForExistence(timeout: 12))
        app.tab("勤務先").tap()
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
        XCTAssertTrue(app.buttons["workplace.card"].waitForExistence(timeout: 6))

        app.tab("カレンダー").tap()
        let add = app.buttons["calendar.part.add"]
        scrollTo(app, add)
        add.tap()
        let field = app.textFields["field.パターン名"]
        XCTAssertTrue(field.waitForExistence(timeout: 6))
        field.tap()
        field.typeText("朝")
        if app.keyboards.buttons["完了"].exists { app.keyboards.buttons["完了"].tap() }
        app.buttons["pattern.save"].tap()

        let row = app.buttons["calendar.pattern.朝"]
        scrollTo(app, row)
        XCTAssertTrue(row.exists)
        row.tap()
        let result = app.staticTexts["pattern.result"]
        XCTAssertTrue(result.waitForExistence(timeout: 4))
        XCTAssertTrue(result.label.contains("1件置きました"))
        XCTAssertTrue(app.buttons["calendar.shift"].waitForExistence(timeout: 4))

        // 取り消す removes exactly the shift that tap added.
        let undo = app.buttons["pattern.undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 4))
        undo.tap()
        XCTAssertTrue(app.staticTexts["pattern.result"].label.contains("取り消しました"))
        XCTAssertFalse(app.buttons["calendar.shift"].exists)

        // Rename through the pencil.
        let edit = app.buttons["calendar.pattern.edit.朝"]
        scrollTo(app, edit)
        edit.tap()
        let renamed = app.textFields["field.パターン名"]
        XCTAssertTrue(renamed.waitForExistence(timeout: 6))
        renamed.tap()
        renamed.typeText("早")
        if app.keyboards.buttons["完了"].exists { app.keyboards.buttons["完了"].tap() }
        app.buttons["pattern.save"].tap()
        XCTAssertTrue(app.buttons["calendar.pattern.朝早"].waitForExistence(timeout: 6))

        // Delete it.
        let edit2 = app.buttons["calendar.pattern.edit.朝早"]
        scrollTo(app, edit2)
        edit2.tap()
        let delete = app.buttons["pattern.delete"]
        scrollTo(app, delete)
        delete.tap()
        app.alerts.buttons["削除"].tap()
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: app.buttons["calendar.pattern.朝早"], handler: nil)
        waitForExpectations(timeout: 6)
    }

    /// A control under the tab bar still reports hittable, so keep its frame in
    /// the open part of the screen before tapping.
    private func scrollTo(_ app: XCUIApplication, _ element: XCUIElement) {
        _ = element.waitForExistence(timeout: 6)
        let top: CGFloat = 90
        let bottom = app.frame.maxY - 120
        for _ in 0..<10 {
            let frame = element.frame
            if element.isHittable && frame.minY > top && frame.maxY < bottom { return }
            if frame.minY < top {
                app.swipeDown()
            } else {
                app.swipeUp()
            }
        }
    }
}
