import Foundation
import Testing
@testable import ShiftTrack

struct ShiftOverlapBoundaryTests {
    private static let calendar: Calendar = ShiftOverlap.tokyo
    private static let placeA = UUID()
    private static let placeB = UUID()

    @Test(arguments: samples)
    func boundaries(_ sample: Sample) {
        let hits = compare(sample)
        switch sample.expect {
        case .none:
            #expect(hits.isEmpty)
        case .time:
            #expect(hits.count == 1)
            #expect(hits.first?.kind == .time)
        case .sameDay:
            #expect(hits.count == 1)
            #expect(hits.first?.kind == .sameDay)
        case .travel(let minutes):
            #expect(hits.count == 1)
            #expect(hits.first?.kind == .travel(minutes: minutes))
        }
    }

    @Test
    func secondsAreTruncatedBeforeTheCompare() {
        let end = date(year: 2026, month: 11, day: 12, hour: 12, minute: 0, second: 45)
        let start = date(year: 2026, month: 11, day: 12, hour: 12, minute: 0, second: 10)
        let proposed = ShiftOverlap.Span(id: "a", workplace: Self.placeA, name: "架空茶房", start: date(year: 2026, month: 11, day: 12, hour: 9, minute: 0, second: 30), end: end, startMinutes: 9 * 60, endMinutes: 12 * 60)
        let other = ShiftOverlap.Span(id: "b", workplace: Self.placeB, name: "架空書店", start: start, end: date(year: 2026, month: 11, day: 12, hour: 15, minute: 0, second: 5), startMinutes: 12 * 60, endMinutes: 15 * 60)
        let hits = ShiftOverlap.conflicts(of: proposed, among: [other], travelMinutes: 0, calendar: Self.calendar)
        #expect(hits.isEmpty)
    }

    @Test
    func theShiftBeingEditedIsExcluded() {
        let span = ShiftOverlap.span(id: "self", name: "架空茶房", workplace: Self.placeA, day: day(0), start: 9 * 60, end: 18 * 60, calendar: Self.calendar)
        let hits = ShiftOverlap.conflicts(of: span, among: [span], travelMinutes: 30, calendar: Self.calendar)
        #expect(hits.isEmpty)
    }

    @Test
    func aCancelledShiftIsExcluded() {
        let proposed = ShiftOverlap.span(id: "new", name: "架空茶房", workplace: Self.placeA, day: day(0), start: 9 * 60, end: 18 * 60, calendar: Self.calendar)
        var other = ShiftOverlap.span(id: "old", name: "架空書店", workplace: Self.placeB, day: day(0), start: 10 * 60, end: 12 * 60, calendar: Self.calendar)
        other.cancelled = true
        let hits = ShiftOverlap.conflicts(of: proposed, among: [other], travelMinutes: 30, calendar: Self.calendar)
        #expect(hits.isEmpty)
    }

    @Test
    func threeHitsComeBackInStartOrder() {
        let proposed = ShiftOverlap.span(id: "new", name: "架空茶房", workplace: Self.placeA, day: day(0), start: 8 * 60, end: 20 * 60, calendar: Self.calendar)
        let late = ShiftOverlap.span(id: "c", name: "晩", workplace: Self.placeB, day: day(0), start: 18 * 60, end: 21 * 60, calendar: Self.calendar)
        let early = ShiftOverlap.span(id: "a", name: "朝", workplace: Self.placeB, day: day(0), start: 7 * 60, end: 9 * 60, calendar: Self.calendar)
        let mid = ShiftOverlap.span(id: "b", name: "昼", workplace: Self.placeB, day: day(0), start: 12 * 60, end: 13 * 60, calendar: Self.calendar)
        let hits = ShiftOverlap.conflicts(of: proposed, among: [late, early, mid], travelMinutes: 0, calendar: Self.calendar)
        #expect(hits.map(\.otherID) == ["a", "b", "c"])
    }

    @Test
    func aChangedDeviceTimeZoneDoesNotChangeTheResult() {
        let before = NSTimeZone.default
        NSTimeZone.default = TimeZone(identifier: "Pacific/Honolulu")!
        defer { NSTimeZone.default = before }
        let sample = Sample(day: 0, start: 9 * 60, end: 12 * 60, otherDay: 0, otherStart: 12 * 60, otherEnd: 15 * 60, samePlace: false, travel: 30, expect: .travel(minutes: 0))
        let hits = compare(sample)
        #expect(hits.count == 1)
        #expect(hits.first?.kind == .travel(minutes: 0))
        #expect(hits.first?.start == date(year: 2026, month: 11, day: 12, hour: 12, minute: 0, second: 0))
    }

    @Test
    func sameWorkplaceOnTheSameDayUsesOurOwnSentence() {
        let hits = compare(Sample(day: 0, start: 9 * 60, end: 12 * 60, otherDay: 0, otherStart: 16 * 60, otherEnd: 18 * 60, samePlace: true, travel: 0, expect: .sameDay))
        #expect(hits.count == 1)
        #expect(ShiftOverlap.row(hits[0]) == "架空書店（16:00〜18:00）は、同じ勤務先のこの日に入っています。")
    }

    @Test
    func newShiftsInOneBatchAreComparedWithEachOther() {
        let first = ShiftOverlap.span(id: "n1", name: "架空茶房", workplace: Self.placeA, day: day(0), start: 9 * 60, end: 12 * 60, calendar: Self.calendar)
        let second = ShiftOverlap.span(id: "n2", name: "架空書店", workplace: Self.placeB, day: day(0), start: 12 * 60 + 10, end: 15 * 60, calendar: Self.calendar)
        let hits = ShiftOverlap.conflicts(batch: [first, second], existing: [], travelMinutes: 30, calendar: Self.calendar)
        #expect(hits.count == 1)
        #expect(hits.first?.kind == .travel(minutes: 10))
    }

    private func compare(_ sample: Sample) -> [ShiftOverlap.Hit] {
        let proposed = ShiftOverlap.span(id: "new", name: "架空茶房", workplace: Self.placeA, day: day(sample.day, year: sample.year, month: sample.month), start: sample.start, end: sample.end, calendar: Self.calendar)
        let other = ShiftOverlap.span(id: "old", name: "架空書店", workplace: sample.samePlace ? Self.placeA : Self.placeB, day: day(sample.otherDay, year: sample.year, month: sample.month), start: sample.otherStart, end: sample.otherEnd, calendar: Self.calendar)
        return ShiftOverlap.conflicts(of: proposed, among: [other], travelMinutes: sample.travel, calendar: Self.calendar)
    }

    private func day(_ offset: Int, year: Int = 2026, month: Int = 11) -> Date {
        let start = date(year: year, month: month, day: 12, hour: 0, minute: 0, second: 0)
        return Self.calendar.date(byAdding: .day, value: offset, to: start) ?? start
    }

    private func date(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int) -> Date {
        Self.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
    }

    private static let samples: [Sample] = [
        Sample(day: 0, start: 9 * 60, end: 9 * 60, otherDay: 0, otherStart: 9 * 60, otherEnd: 12 * 60, samePlace: false, travel: 0, expect: .none),
        Sample(day: 0, start: 9 * 60, end: 12 * 60, otherDay: 0, otherStart: 12 * 60, otherEnd: 15 * 60, samePlace: false, travel: 0, expect: .none),
        Sample(day: 0, start: 9 * 60, end: 12 * 60 + 1, otherDay: 0, otherStart: 12 * 60, otherEnd: 15 * 60, samePlace: false, travel: 0, expect: .time),
        Sample(day: 0, start: 9 * 60, end: 18 * 60, otherDay: 0, otherStart: 10 * 60, otherEnd: 11 * 60, samePlace: true, travel: 30, expect: .time),
        Sample(day: 0, start: 9 * 60, end: 18 * 60, otherDay: 0, otherStart: 9 * 60, otherEnd: 18 * 60, samePlace: false, travel: 0, expect: .time),
        Sample(day: 0, start: 9 * 60, end: 12 * 60, otherDay: 0, otherStart: 12 * 60 + 29, otherEnd: 15 * 60, samePlace: false, travel: 30, expect: .travel(minutes: 29)),
        Sample(day: 0, start: 9 * 60, end: 12 * 60, otherDay: 0, otherStart: 12 * 60 + 30, otherEnd: 15 * 60, samePlace: false, travel: 30, expect: .none),
        Sample(day: 0, start: 9 * 60, end: 12 * 60, otherDay: 0, otherStart: 12 * 60 + 31, otherEnd: 15 * 60, samePlace: false, travel: 30, expect: .none),
        Sample(day: 0, start: 9 * 60, end: 12 * 60, otherDay: 0, otherStart: 12 * 60 + 10, otherEnd: 15 * 60, samePlace: false, travel: 0, expect: .none),
        Sample(day: 0, start: 9 * 60, end: 12 * 60, otherDay: 0, otherStart: 12 * 60 + 10, otherEnd: 15 * 60, samePlace: true, travel: 30, expect: .sameDay),
        Sample(day: 0, start: 9 * 60, end: 12 * 60, otherDay: 1, otherStart: 14 * 60, otherEnd: 17 * 60, samePlace: true, travel: 30, expect: .none),
        Sample(day: 0, start: 9 * 60, end: 12 * 60, otherDay: 0, otherStart: 12 * 60 + 10, otherEnd: 15 * 60, samePlace: false, travel: 30, expect: .travel(minutes: 10)),
        Sample(day: 0, start: 22 * 60, end: 2 * 60, otherDay: 1, otherStart: 1 * 60, otherEnd: 3 * 60, samePlace: false, travel: 0, expect: .time),
        Sample(day: 0, start: 22 * 60, end: 0, otherDay: 1, otherStart: 0, otherEnd: 8 * 60, samePlace: false, travel: 0, expect: .none),
        Sample(day: 49, start: 22 * 60, end: 2 * 60, otherDay: 50, otherStart: 1 * 60, otherEnd: 3 * 60, samePlace: true, travel: 0, expect: .time, year: 2026, month: 11),
        Sample(day: 16, start: 22 * 60, end: 2 * 60, otherDay: 17, otherStart: 1 * 60, otherEnd: 3 * 60, samePlace: false, travel: 0, expect: .time, year: 2024, month: 2)
    ]
}

struct Sample: Sendable {
    var day: Int
    var start: Int
    var end: Int
    var otherDay: Int
    var otherStart: Int
    var otherEnd: Int
    var samePlace: Bool
    var travel: Int
    var expect: Expect
    var year: Int = 2026
    var month: Int = 11

    enum Expect: Equatable, Sendable {
        case none
        case time
        case sameDay
        case travel(minutes: Int)
    }
}
