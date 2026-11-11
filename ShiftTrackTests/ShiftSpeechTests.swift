import Testing
@testable import ShiftTrack

struct ShiftSpeechTests {
    @Test
    func speaksWorkplaceTimeAndYenTogether() {
        let line = ShiftSpeech.line(name: "架空茶房", schedule: "10:00–18:00", yen: "9,600円")
        #expect(line == "架空茶房、10:00–18:00、9,600円")
    }
}
