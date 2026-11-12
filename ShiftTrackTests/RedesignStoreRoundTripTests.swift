import Foundation
import SwiftData
import Testing
@testable import ShiftTrack

/// The redesign adds no SwiftData field: every new setting uses an existing
/// field or UserDefaults. This test writes a store full of fictional data,
/// reopens it with the current schema, and checks every field the redesigned
/// screens read, plus the pay numbers derived from them.
@MainActor
struct RedesignStoreRoundTripTests {
    private static let schema = Schema([
        Workplace.self, WorkShift.self, AppSettings.self,
        ShiftPattern.self, ShiftRequest.self, ShiftPart.self
    ])

    private static var tokyo: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }

    private static func noon(_ year: Int, _ month: Int, _ day: Int) -> Date {
        tokyo.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    @Test
    func everyFieldTheRedesignReadsSurvivesReopening() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("shifttrack-redesign-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("store.sqlite")
        let day = Self.noon(2026, 11, 12)
        let fixedNow = Self.tokyo.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 23, minute: 30))!

        var expectedYen: [UUID: Int] = [:]
        var expectedEarned: Int?
        var placeID = UUID()
        var nightShiftID = UUID()

        do {
            let container = try ModelContainer(for: Self.schema, configurations: [ModelConfiguration(url: url)])
            let context = container.mainContext

            let place = Workplace(name: "架空茶房 北窓", colorHex: "A9C7F5", hourlyWage: 1_150, transportAllowance: 240)
            place.genre = "喫茶"
            place.place = "架空県北窓町1-2"
            place.phone = ""
            place.latitude = 35.1
            place.longitude = 139.2
            place.hasMapCoordinate = true
            place.closingDay = 20
            place.paydayMonthOffset = 1
            place.paydayDay = 10
            place.payCycle = .month
            place.nightPayEnabled = true
            place.nightWage = 0
            place.nightRatePercent = 25
            place.holidayPayEnabled = true
            place.setHolidayWeekdays([1, 7])
            place.holidayWage = 0
            place.setHolidayRatePercents([10, 0, 0, 0, 0, 0, 10])
            place.overtimeEnabled = true
            place.overtimeAfterMinutes = 480
            place.overtimeExtra = 0
            place.overtimeRatePercent = 25
            place.customBreaks = true
            place.breakRules = [.init(overMinutes: 300, breakMinutes: 30)]
            place.wageHistory = [.init(at: Self.noon(2026, 4, 1), hourlyWage: 1_100)]
            place.notes = "制服あり"
            context.insert(place)
            placeID = place.uuid

            let night = WorkShift(
                date: day,
                startMinutes: 22 * 60,
                endMinutes: 5 * 60,
                breakMinutes: 60,
                notes: "仕込みの日",
                customPay: nil,
                adjustmentYen: -300,
                adjustmentNote: "まかない",
                todosRaw: ShiftTodoCodec.encode([
                    ShiftTodoCodec.Item(id: UUID(), title: "看板を出す", done: true),
                    ShiftTodoCodec.Item(id: UUID(), title: "閉店前にレジを締める", done: false),
                ]),
                workplace: place,
                attendanceConfirmed: false,
                destinationName: "本店",
                destinationPlace: "架空県南窓町3-4"
            )
            context.insert(night)
            nightShiftID = night.uuid
            let fixed = WorkShift(date: Self.noon(2026, 11, 14), startMinutes: 10 * 60, endMinutes: 15 * 60, breakMinutes: 0, customPay: 7_000, workplace: place)
            context.insert(fixed)

            let settings = AppSettings(weekStartsOnMonday: true, includeTransport: true, defaultHourlyWage: 1_150, defaultTransportAllowance: 240, annualIncomeGoal: 1_200_000, monthlyIncomeGoal: 90_000)
            settings.setMonthGoal(80_000, year: 2026, month: 12, applyForward: false)
            context.insert(settings)

            context.insert(ShiftPart(
                name: "遅番",
                workplaceUUID: place.uuid,
                startMinute: 17 * 60,
                endMinute: 22 * 60,
                breakMinutes: 0,
                defaultTodosRaw: ShiftTodoCodec.encode([ShiftTodoCodec.Item(id: UUID(), title: "看板を入れる", done: false)]),
                colorHex: "F3D98A",
                breakModeRaw: PatternBreakMode.workplace.rawValue
            ))
            context.insert(ShiftPattern(
                name: "平日の遅番",
                workplaceUUID: place.uuid,
                startMinutes: 17 * 60,
                endMinutes: 22 * 60,
                breakMinutes: 0,
                weekdays: [2, 4],
                breakModeRaw: PatternBreakMode.fixed.rawValue
            ))
            context.insert(ShiftRequest(
                date: Self.noon(2026, 11, 20),
                startMinutes: 9 * 60,
                endMinutes: 13 * 60,
                breakMinutes: 0,
                note: "午前だけ",
                workplaceUUID: place.uuid,
                kindRaw: ShiftRequestKind.hopedRest
            ))
            try context.save()

            for shift in [night, fixed] {
                expectedYen[shift.uuid] = PayMath.shiftYen(shift, includeTransport: true, calendar: Self.tokyo)
            }
            expectedEarned = EarningsSoFar.progress(for: night, now: fixedNow, calendar: Self.tokyo)?.earnedYen
        }

        let reopened = try ModelContainer(for: Self.schema, configurations: [ModelConfiguration(url: url)])
        let context = reopened.mainContext

        let places = try context.fetch(FetchDescriptor<Workplace>())
        #expect(places.count == 1)
        let place = try #require(places.first)
        #expect(place.uuid == placeID)
        #expect(place.name == "架空茶房 北窓")
        #expect(place.hourlyWage == 1_150)
        #expect(place.transportAllowance == 240)
        #expect(place.place == "架空県北窓町1-2")
        #expect(place.phone.isEmpty)
        #expect(place.hasMapCoordinate)
        #expect(place.closingDay == 20)
        #expect(place.paydayMonthOffset == 1)
        #expect(place.paydayDay == 10)
        #expect(place.payCycle == .month)
        #expect(place.nightPayEnabled && place.nightWage == 0 && place.nightRatePercent == 25)
        #expect(place.holidayPayEnabled && place.holidayWeekdays == [1, 7])
        #expect(place.holidayRatePercents == [10, 0, 0, 0, 0, 0, 10])
        #expect(place.overtimeEnabled && place.overtimeRatePercent == 25 && place.overtimeExtra == 0)
        #expect(place.customBreaks)
        #expect(place.breakRules.map(\.breakMinutes) == [30])
        #expect(place.wageHistory.map(\.hourlyWage) == [1_100])
        #expect(WorkplaceContact.mapReason(for: place) == nil)
        #expect(WorkplaceContact.phoneReason(for: place) == WorkplaceContact.missingPhone)

        let shifts = try context.fetch(FetchDescriptor<WorkShift>())
        #expect(shifts.count == 2)
        let night = try #require(shifts.first { $0.uuid == nightShiftID })
        #expect(night.startMinutes == 22 * 60 && night.endMinutes == 5 * 60 && night.breakMinutes == 60)
        #expect(night.adjustmentYen == -300 && night.adjustmentNote == "まかない")
        #expect(night.todos.map(\.title) == ["看板を出す", "閉店前にレジを締める"])
        #expect(night.todos.map(\.done) == [true, false])
        #expect(night.destinationName == "本店")
        #expect(night.attendanceConfirmed == false)
        #expect(night.workplace?.uuid == placeID)
        for shift in shifts {
            #expect(PayMath.shiftYen(shift, includeTransport: true, calendar: Self.tokyo) == expectedYen[shift.uuid])
        }
        #expect(EarningsSoFar.progress(for: night, now: fixedNow, calendar: Self.tokyo)?.earnedYen == expectedEarned)
        #expect((expectedEarned ?? 0) > 0)

        let settings = try #require(try context.fetch(FetchDescriptor<AppSettings>()).first)
        #expect(settings.weekStartsOnMonday)
        #expect(settings.monthGoal(year: 2026, month: 12) == 80_000)
        #expect(settings.monthGoal(year: 2026, month: 11) == 90_000)
        #expect(settings.yearGoal(2026) == 1_200_000)

        let part = try #require(try context.fetch(FetchDescriptor<ShiftPart>()).first)
        #expect(part.name == "遅番" && part.colorHex == "F3D98A")
        #expect(part.breakModeRaw == PatternBreakMode.workplace.rawValue)
        #expect(part.defaultTodos.map(\.title) == ["看板を入れる"])

        let pattern = try #require(try context.fetch(FetchDescriptor<ShiftPattern>()).first)
        #expect(pattern.weekdays == [2, 4])

        let request = try #require(try context.fetch(FetchDescriptor<ShiftRequest>()).first)
        #expect(request.kindRaw == ShiftRequestKind.hopedRest)
        #expect(request.isOpen)
        #expect(request.note == "午前だけ")
    }
}
