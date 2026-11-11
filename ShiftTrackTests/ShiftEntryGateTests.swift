import Foundation
import Testing
@testable import ShiftTrack

struct ShiftEntryGateTests {
    private static let now = ShiftOverlap.tokyo.date(
        from: DateComponents(year: 2026, month: 11, day: 11, hour: 9, minute: 0)
    )!

    @Test
    func aCompleteSentenceDoesNotAskTheModel() async {
        let filler = CountingFiller()
        let reading = await ShiftEntryGate.resolve(
            text: "明日10時から18時 架空茶房",
            now: Self.now,
            calendar: ShiftOverlap.tokyo,
            filler: filler
        )
        #expect(reading?.canSave == true)
        #expect(filler.calls == 0)
    }

    @Test
    func anUnreadSentenceMayAskTheModelAndStillRequiresASaveableReading() async {
        let filler = CountingFiller()
        let reading = await ShiftEntryGate.resolve(
            text: "来週の土曜 朝9時〜夕方5時",
            now: Self.now,
            calendar: ShiftOverlap.tokyo,
            filler: filler
        )
        #expect(filler.calls == 1)
        #expect(reading == nil)
    }
}

private final class CountingFiller: ShiftSentenceFilling, @unchecked Sendable {
    var calls = 0

    func fill(_ text: String) async -> TypedShiftEntry.Reading? {
        calls += 1
        return nil
    }
}
