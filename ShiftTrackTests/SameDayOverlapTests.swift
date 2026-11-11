import XCTest
@testable import ShiftTrack

final class ShiftOverlapTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }

    private var day: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 12))!
    }

    private let placeA = UUID()
    private let placeB = UUID()

    func testPartialOverlapMatchesTheDialogCase() {
        XCTAssertEqual(
            kind(start: 9 * 60 + 30, end: 18 * 60, place: placeA, otherStart: 11 * 60 + 30, otherEnd: 20 * 60 + 30, otherDay: day, otherPlace: placeB),
            .time
        )
    }

    func testTouchingEndpointsDoNotOverlap() {
        XCTAssertNil(kind(
            start: 9 * 60, end: 12 * 60, place: placeA,
            otherStart: 12 * 60, otherEnd: 15 * 60, otherDay: day, otherPlace: placeB,
            travel: 0
        ))
    }

    func testOvernightDoesNotOverlapAnEarlierSameDayShift() {
        XCTAssertNil(kind(
            start: 22 * 60, end: 6 * 60, place: placeA,
            otherStart: 9 * 60, otherEnd: 18 * 60, otherDay: day, otherPlace: placeB,
            travel: 0
        ))
        XCTAssertNil(kind(
            start: 9 * 60, end: 18 * 60, place: placeA,
            otherStart: 20 * 60, otherEnd: 2 * 60, otherDay: day, otherPlace: placeB,
            travel: 0
        ))
    }

    func testOvernightReachesTheNextMorning() {
        let next = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day))!
        XCTAssertEqual(
            kind(start: 22 * 60, end: 6 * 60, place: placeA, otherStart: 5 * 60, otherEnd: 9 * 60, otherDay: next, otherPlace: placeB, travel: 0),
            .time
        )
    }

    func testSameWorkplaceOnTheSameDayWithoutAClockOverlap() {
        XCTAssertEqual(
            kind(start: 9 * 60, end: 12 * 60, place: placeA, otherStart: 14 * 60, otherEnd: 18 * 60, otherDay: day, otherPlace: placeA, travel: 30),
            .existingShift
        )
    }

    func testShortGapBetweenDifferentWorkplaces() {
        XCTAssertEqual(
            kind(start: 9 * 60, end: 12 * 60, place: placeA, otherStart: 12 * 60 + 20, otherEnd: 15 * 60, otherDay: day, otherPlace: placeB, travel: 30),
            .travel(minutes: 20)
        )
    }

    func testGapAtTheTravelThresholdIsClear() {
        XCTAssertNil(kind(
            start: 9 * 60, end: 12 * 60, place: placeA,
            otherStart: 12 * 60 + 30, otherEnd: 15 * 60, otherDay: day, otherPlace: placeB,
            travel: 30
        ))
    }

    func testZeroTravelMinutesSkipsTheGap() {
        XCTAssertNil(kind(
            start: 9 * 60, end: 12 * 60, place: placeA,
            otherStart: 12 * 60 + 10, otherEnd: 15 * 60, otherDay: day, otherPlace: placeB,
            travel: 0
        ))
    }

    private func kind(
        start: Int,
        end: Int,
        place: UUID,
        otherStart: Int,
        otherEnd: Int,
        otherDay: Date,
        otherPlace: UUID,
        travel: Int = 30
    ) -> ShiftOverlap.Kind? {
        ShiftOverlap.classify(
            start: start,
            end: end,
            day: day,
            workplace: place,
            otherStart: otherStart,
            otherEnd: otherEnd,
            otherDay: otherDay,
            otherWorkplace: otherPlace,
            travelMinutes: travel,
            calendar: calendar
        )
    }
}
