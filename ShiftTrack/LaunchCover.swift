import Foundation

/// Launch cover timing from the recovered call that either waits or springs.
/// The return bit is this app's own flag: it is set when the scene goes to
/// the background, so the next process launch is a return.
enum LaunchCover {
    static let returnKey = "shifttrack.launchReturn"
    static let holdSeconds = 0.8
    static let springResponse = 0.55
    static let springDamping = 0.68
    static let springDelay = 0.15

    enum Motion: Equatable {
        case hold(seconds: Double)
        case spring(response: Double, dampingFraction: Double, delay: Double)
    }

    static func returnFlag(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: returnKey)
    }

    static func markReturn(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: returnKey)
    }

    /// A set return flag waits. Anything else uses the delayed spring.
    static func motion(returnFlag: Bool) -> Motion {
        if returnFlag {
            return .hold(seconds: holdSeconds)
        }
        return .spring(response: springResponse, dampingFraction: springDamping, delay: springDelay)
    }
}
