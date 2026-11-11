import UserNotifications
import XCTest
@testable import ShiftTrack

final class ConfirmedAccessTests: XCTestCase {
    func testSymbolsStayOnTheNamedScreens() {
        XCTAssertEqual(ConfirmedSymbols.aboutChevron, "chevron.right")
        XCTAssertEqual(ConfirmedSymbols.aboutArrow, "arrow.up.right")
        XCTAssertEqual(ConfirmedSymbols.planner, "briefcase.fill")
        XCTAssertEqual(ConfirmedSymbols.hoursStockClose, "xmark")
        XCTAssertEqual(ConfirmedSymbols.todoMark(done: false), "circle")
        XCTAssertNil(ConfirmedSymbols.todoMark(done: true))
    }

    func testNotificationOptionsAreAlertSoundAndBadge() {
        XCTAssertEqual(SettingsAccess.notificationOptions, [.alert, .sound, .badge])
        XCTAssertEqual(SettingsAccess.notificationOptionBits, 7)
    }

    func testReverseGeocodeFillsOnlyAnEmptyUnreadAddress() {
        let parts = ImportReverseGeocode.Parts(
            administrativeArea: "千葉県",
            locality: "木更津市",
            subLocality: "架空",
            thoroughfare: "北窓",
            subThoroughfare: "1-2-3"
        )
        XCTAssertEqual(ImportReverseGeocode.address(from: parts), "千葉県木更津市架空北窓1-2-3")
        XCTAssertEqual(
            ImportReverseGeocode.address(from: ImportReverseGeocode.Parts(locality: "  ", thoroughfare: "北窓")),
            "北窓"
        )
        XCTAssertTrue(ImportReverseGeocode.shouldFill(current: "  ", edited: false))
        XCTAssertFalse(ImportReverseGeocode.shouldFill(current: "東京都架空区", edited: false))
        XCTAssertFalse(ImportReverseGeocode.shouldFill(current: "", edited: true))
    }
}
