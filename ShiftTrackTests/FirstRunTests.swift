import Foundation
import Testing
@testable import ShiftTrack

struct FirstRunTests {
    @Test
    func existingDataSkipsAndRemembers() {
        let defaults = UserDefaults(suiteName: "first-run-tests")!
        defaults.removePersistentDomain(forName: "first-run-tests")
        #expect(FirstRun.shouldShow(hasContent: true, defaults: defaults) == false)
        #expect(defaults.bool(forKey: FirstRun.key))
        #expect(FirstRun.shouldShow(hasContent: false, defaults: defaults) == false)
    }

    @Test
    func anEmptyInstallShowsUntilFinished() {
        let defaults = UserDefaults(suiteName: "first-run-empty")!
        defaults.removePersistentDomain(forName: "first-run-empty")
        #expect(FirstRun.shouldShow(hasContent: false, defaults: defaults))
        FirstRun.finish(defaults: defaults)
        #expect(FirstRun.shouldShow(hasContent: false, defaults: defaults) == false)
    }
}
