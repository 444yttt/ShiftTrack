import Foundation

/// Fills the message template used by the メッセージ action.
///
/// Tokens: `{宛名}` (addressee), `{理由}` (reason) and `{遅れ}` (delay).
/// A line that still holds `{宛名}` is dropped when the addressee is empty,
/// so the template does not leave a blank greeting.
enum LateMessageFill {
    static let addressee = "{宛名}"
    static let reason = "{理由}"
    static let delay = "{遅れ}"

    /// Default template (ていねい).
    static let polite = "{宛名}\nお疲れさまです。{理由}、{遅れ}。\n着きしだい、すぐに入ります。ご迷惑をおかけしてすみません。"
    /// Shorter template (短め).
    static let casual = "{宛名}\n{理由}、{遅れ}。急いで向かいます。"

    static let templateKey = "late.message.template"

    static func apply(template: String, addressee: String, reason: String, delay: String) -> String {
        let name = addressee.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = template.components(separatedBy: "\n").filter { line in
            !(name.isEmpty && line.contains(Self.addressee))
        }
        return lines
            .joined(separator: "\n")
            .replacingOccurrences(of: Self.addressee, with: name)
            .replacingOccurrences(of: Self.reason, with: reason)
            .replacingOccurrences(of: Self.delay, with: delay)
    }
}
