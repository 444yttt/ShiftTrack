import XCTest

extension XCUIApplication {
    /// An item of the system tab bar, by its title: ホーム, カレンダー, 給料, 勤務先, 設定.
    /// Matched on the label and taken as the first match, so an extra element the
    /// bar draws for its selection can never make the query ambiguous.
    func tab(_ title: String) -> XCUIElement {
        tabBars.buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch
    }
}
