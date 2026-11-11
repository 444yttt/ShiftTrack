import Foundation
import Testing
@testable import ShiftTrack

struct TypedShiftEntryTests {
    private static let tokyo = ShiftOverlap.tokyo

    private static let now = ShiftOverlap.tokyo.date(
        from: DateComponents(year: 2026, month: 11, day: 11, hour: 9, minute: 0)
    )!

    @Test(arguments: [
        Sample("明日10時から18時 架空茶房", month: 11, day: 12, start: 600, end: 1080, canSave: true, workplace: "架空茶房"),
        Sample("12/24 17-22", month: 12, day: 24, start: 1020, end: 1320, canSave: true, workplace: "架空茶房", defaultWorkplace: "架空茶房"),
        Sample("25日 18時半-翌5時 休憩60分 架空茶房", month: 11, day: 25, start: 1110, end: 300, breakMinutes: 60, canSave: true, workplace: "架空茶房"),
        Sample("毎週火木 17-22", start: 1020, end: 1320, canSave: false, repeats: true, weekdays: [3, 5]),
        Sample("10-6 架空茶房", start: 600, end: 1080, canSave: true, alternative: true, workplace: "架空茶房"),
        Sample("火曜日 17-22 架空茶房", month: 11, day: 17, start: 1020, end: 1320, canSave: true, workplace: "架空茶房"),
        Sample("2/30 10-18 架空茶房", canSave: false),
        Sample("１７－２２ 架空茶房", start: 1020, end: 1320, canSave: true, workplace: "架空茶房"),
        Sample("ｶﾀｶﾅ 17-22", start: 1020, end: 1320, canSave: true, workplace: "ｶﾀｶﾅ"),
        Sample("22-5 架空茶房", start: 1320, end: 300, canSave: true, workplace: "架空茶房"),
        Sample("8時-翌2時 架空茶房", start: 480, end: 120, canSave: false, workplace: "架空茶房"),
    ])
    func readsASentence(_ sample: Sample) {
        let reading = TypedShiftEntry.read(
            text: sample.text,
            now: Self.now,
            calendar: Self.tokyo,
            knownNames: sample.known,
            defaultWorkplace: sample.defaultWorkplace
        )
        #expect(reading?.canSave == sample.canSave)
        #expect(reading?.repeatsWeekly == sample.repeats)
        #expect(reading?.alternativeNoted == sample.alternative)
        if let month = sample.month { #expect(reading?.month == month) }
        if let day = sample.day { #expect(reading?.day == day) }
        if let start = sample.start { #expect(reading?.startMinutes == start) }
        if let end = sample.end { #expect(reading?.endMinutes == end) }
        if let workplace = sample.workplace { #expect(reading?.workplaceText == workplace) }
        if let minutes = sample.breakMinutes { #expect(reading?.breakMinutes == minutes) }
        if sample.repeats { #expect(reading?.weekdays == sample.weekdays) }
        if sample.canSave { #expect(reading?.year == 2026) }
    }

    @Test
    func twoWorkplacesAreNotGuessed() {
        let reading = TypedShiftEntry.read(
            text: "明日 17-22 架空茶房 北窓",
            now: Self.now,
            calendar: Self.tokyo,
            knownNames: ["架空茶房", "北窓"]
        )
        #expect(reading?.canSave == false)
        #expect(reading?.workplaceText == "")
    }

    @Test
    func phrasesOutsideTheRulesStayUnread() {
        let reading = TypedShiftEntry.read(
            text: "来週の土曜 朝9時〜夕方5時",
            now: Self.now,
            calendar: Self.tokyo
        )
        #expect(reading == nil)
    }

    @Test
    func aJapaneseCalendarStillResolvesAGregorianDay() {
        var japanese = Calendar(identifier: .japanese)
        japanese.timeZone = Self.tokyo.timeZone
        let reading = TypedShiftEntry.read(
            text: "明日10時から18時 架空茶房",
            now: Self.now,
            calendar: japanese
        )
        #expect(reading?.year == 2026)
        #expect(reading?.month == 11)
        #expect(reading?.day == 12)
    }

    struct Sample: Sendable, CustomTestStringConvertible {
        var text: String
        var month: Int?
        var day: Int?
        var start: Int?
        var end: Int?
        var breakMinutes: Int?
        var canSave: Bool
        var repeats: Bool
        var weekdays: [Int]
        var alternative: Bool
        var workplace: String?
        var known: [String]
        var defaultWorkplace: String

        init(
            _ text: String,
            month: Int? = nil,
            day: Int? = nil,
            start: Int? = nil,
            end: Int? = nil,
            breakMinutes: Int? = nil,
            canSave: Bool,
            repeats: Bool = false,
            weekdays: [Int] = [],
            alternative: Bool = false,
            workplace: String? = nil,
            known: [String] = [],
            defaultWorkplace: String = ""
        ) {
            self.text = text
            self.month = month
            self.day = day
            self.start = start
            self.end = end
            self.breakMinutes = breakMinutes
            self.canSave = canSave
            self.repeats = repeats
            self.weekdays = weekdays
            self.alternative = alternative
            self.workplace = workplace
            self.known = known
            self.defaultWorkplace = defaultWorkplace
        }

        var testDescription: String { text }
    }
}
