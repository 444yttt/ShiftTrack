import XCTest
@testable import ShiftTrack

final class ShiftEndCueTests: XCTestCase {
    func testAnEndInsideTheForegroundGapBuzzesOnce() {
        let previous = Date(timeIntervalSince1970: 1_000)
        let end = previous.addingTimeInterval(1)
        let now = previous.addingTimeInterval(2)
        let id = UUID()
        XCTAssertEqual(
            ShiftEndCue.crossed(previous: previous, now: now, moments: [.init(id: id, end: end)]),
            [id]
        )
    }

    func testAnEndAlreadyBehindThePreviousTickDoesNotBuzz() {
        let previous = Date(timeIntervalSince1970: 1_000)
        let now = previous.addingTimeInterval(1)
        let id = UUID()
        XCTAssertTrue(
            ShiftEndCue.crossed(
                previous: previous,
                now: now,
                moments: [.init(id: id, end: previous.addingTimeInterval(-30))]
            ).isEmpty
        )
    }

    func testAnEndExactlyAtThePreviousTickDoesNotBuzzAgain() {
        let previous = Date(timeIntervalSince1970: 1_000)
        let id = UUID()
        XCTAssertTrue(
            ShiftEndCue.crossed(
                previous: previous,
                now: previous.addingTimeInterval(1),
                moments: [.init(id: id, end: previous)]
            ).isEmpty
        )
    }

    func testAnEndStillInTheFutureDoesNotBuzz() {
        let previous = Date(timeIntervalSince1970: 1_000)
        let now = previous.addingTimeInterval(1)
        let id = UUID()
        XCTAssertTrue(
            ShiftEndCue.crossed(
                previous: previous,
                now: now,
                moments: [.init(id: id, end: now.addingTimeInterval(10))]
            ).isEmpty
        )
    }
}
