import XCTest

extension XCUIApplication {
    /// An item of the system tab bar, by its title: ホーム, カレンダー, 給料, 勤務先, 設定.
    func tab(_ title: String) -> XCUIElement {
        tabBars.buttons[title]
    }
}
