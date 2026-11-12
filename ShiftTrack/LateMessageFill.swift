import Foundation

/// Fills a late-message template.
///
/// Confirmed: the late screen checks `{宛名}`, `{理由}`, and `{遅れ}` with
/// `contains`, and calls `replacingOccurrences` five times before that.
/// The other two search strings were not recovered, so they are not guessed.
///
/// Inferred: a line that still contains `{宛名}` is dropped when the name is
/// empty. That sentence is in the template editor. The branch itself was not
/// closed in the binary.
enum LateMessageFill {
    static let addressee = "{宛名}"
    static let reason = "{理由}"
    static let delay = "{遅れ}"

    /// Confirmed opening. The following lines only hold the three tokens.
    static let polite = "申し訳ありません。\n{宛名}\n{理由}、{遅れ}"
    /// Confirmed opening. The following lines only hold the three tokens.
    static let casual = "すみません。\n{宛名}\n{理由}、{遅れ}"

    static let explanation = "{宛名} は宛名、{理由} は遅れる理由、{遅れ} は遅れる時間か到着予定に置き換わります。宛名が空のときは、その行を省きます。"

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
