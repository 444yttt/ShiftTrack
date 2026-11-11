import XCTest
@testable import ShiftTrack

final class SameDayOverlapTests: XCTestCase {
    func testPartialOverlapMatchesTheDialogCase() {
        XCTAssertTrue(SameDayOverlap.clocksOverlap(
            start: 9 * 60 + 30,
            end: 18 * 60,
            otherStart: 11 * 60 + 30,
            otherEnd: 20 * 60 + 30
        ))
    }

    func testTouchingEndpointsDoNotOverlap() {
        XCTAssertFalse(SameDayOverlap.clocksOverlap(
            start: 9 * 60,
            end: 12 * 60,
            otherStart: 12 * 60,
            otherEnd: 15 * 60
        ))
    }

    func testOvernightClocksAreNotTreatedAsOverlap() {
        XCTAssertFalse(SameDayOverlap.clocksOverlap(
            start: 22 * 60,
            end: 6 * 60,
            otherStart: 9 * 60,
            otherEnd: 18 * 60
        ))
        XCTAssertFalse(SameDayOverlap.clocksOverlap(
            start: 9 * 60,
            end: 18 * 60,
            otherStart: 20 * 60,
            otherEnd: 2 * 60
        ))
    }
}
