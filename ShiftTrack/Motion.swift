import SwiftUI

enum Motion {
    static let press = Animation.smooth(duration: 0.16)
    static let chip = Animation.snappy(duration: 0.20)
    static let layout = Animation.snappy(duration: 0.25)
    static let settle = Animation.spring(duration: 0.42, bounce: 0.14)

    static func allowed(_ animation: Animation, reduce: Bool) -> Animation? {
        reduce ? nil : animation
    }
}

struct PressableStyle: ButtonStyle {
    var large = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduce || !configuration.isPressed ? 1 : (large ? 0.985 : 0.97))
            .animation(Motion.allowed(Motion.press, reduce: reduce), value: configuration.isPressed)
    }
}
