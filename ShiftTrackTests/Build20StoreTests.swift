import Foundation
import SwiftData
import Testing
@testable import ShiftTrack

/// Reopens a store written by this schema. The build-20 binary is not here, so
/// this cannot load a file that binary produced. The schema change itself is
/// only `breakModeRaw = 0` and `breakRulesRaw = ""` on `ShiftPart` and
/// `ShiftPattern`. Workplace, shift, and the older pattern fields are unchanged.
struct Build20StoreTests {
    @Test
    func reopeningKeepsRowsAndLeavesNewBreakFieldsAtTheirDefaults() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("shifttrack-build20-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("store.sqlite")
        let schema = Schema([
            Workplace.self, WorkShift.self, AppSettings.self,
            ShiftPattern.self, ShiftRequest.self, ShiftPart.self
        ])

        let first = try ModelContainer(for: schema, configurations: [ModelConfiguration(url: url)])
        let context = first.mainContext
        let place = Workplace(name: "架空茶房 北窓", colorHex: "C6F24E", hourlyWage: 1_600, transportAllowance: 0)
        context.insert(place)
        context.insert(WorkShift(
            date: Date(),
            startMinutes: 11 * 60 + 30,
            endMinutes: 20 * 60 + 30,
            breakMinutes: 0,
            workplace: place
        ))
        context.insert(ShiftPart(
            name: "遅番",
            workplaceUUID: place.uuid,
            startMinute: 11 * 60 + 30,
            endMinute: 20 * 60 + 30,
            breakMinutes: 0
        ))
        context.insert(ShiftPattern(
            name: "遅番",
            workplaceUUID: place.uuid,
            startMinutes: 11 * 60 + 30,
            endMinutes: 20 * 60 + 30,
            breakMinutes: 0,
            weekdays: [5]
        ))
        try context.save()

        let again = try ModelContainer(for: schema, configurations: [ModelConfiguration(url: url)])
        let places = try again.mainContext.fetch(FetchDescriptor<Workplace>())
        #expect(places.map(\.name) == ["架空茶房 北窓"])
        #expect(places.first?.hourlyWage == 1_600)
        let shifts = try again.mainContext.fetch(FetchDescriptor<WorkShift>())
        #expect(shifts.count == 1)
        #expect(shifts.first?.startMinutes == 11 * 60 + 30)
        #expect(shifts.first?.endMinutes == 20 * 60 + 30)
        let parts = try again.mainContext.fetch(FetchDescriptor<ShiftPart>())
        #expect(parts.first?.name == "遅番")
        #expect(parts.first?.breakMinutes == 0)
        #expect(parts.first?.breakModeRaw == 0)
        #expect(parts.first?.breakRulesRaw == "")
        let patterns = try again.mainContext.fetch(FetchDescriptor<ShiftPattern>())
        #expect(patterns.first?.breakMinutes == 0)
        #expect(patterns.first?.breakModeRaw == 0)
        #expect(patterns.first?.breakRulesRaw == "")
    }
}
