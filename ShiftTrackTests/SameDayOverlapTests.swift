import XCTest
@testable import ShiftTrack

final class ShiftOverlapLegacyTests: XCTestCase {
    func testTravelMinutesFloorTheSeconds() {
        XCTAssertEqual(ShiftOverlap.shownTravelMinutes(119), 1)
        XCTAssertEqual(ShiftOverlap.shownTravelMinutes(59), 0)
        XCTAssertEqual(ShiftOverlap.shownTravelMinutes(120), 2)
    }
}
