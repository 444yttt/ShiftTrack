import SwiftUI

/// Uniform insets from each screen's own function. `EdgeInsets.init(_all:)`
/// does not name the child, so these values are the screen's, not a named row.
enum ScreenInsets {
    static let root: CGFloat = 16
    static let rootWide: CGFloat = 20
    static let settings: CGFloat = 12
    /// The settings function can skip this inset. Shown unless that branch is taken.
    static let settingsOptional: CGFloat = 8
    static let shiftEditor: CGFloat = 4
    static let todo: CGFloat = 12
    /// The bubble's corner is not in the function. 16 matches the other white cards.
    static let aboutBubbleCorner: CGFloat = 16

    static func settingsInsets(includeOptional: Bool) -> [CGFloat] {
        includeOptional ? [settings, settingsOptional] : [settings]
    }
}

enum LateMessageSection: String, CaseIterable, Identifiable {
    case reason = "① 遅れる理由"
    case delay = "② 遅れる時間"
    case tone = "③ 言葉づかい"
    case note = "文章はここで直せます。①〜③の答えを変えると作り直します。"

    var id: String { rawValue }
}

enum LateMessageLayout {
    /// Each section has its own skip. Hiding one does not drop the others.
    static func sections(hidden: Set<LateMessageSection> = []) -> [LateMessageSection] {
        LateMessageSection.allCases.filter { !hidden.contains($0) }
    }
}

enum ImportSection: String, CaseIterable, Identifiable {
    case mapNote = "住所を Apple のマップサービスに送ります。位置の検索以外には使いません。"
    case readText = "読み取った文字"

    var id: String { rawValue }
}

enum ImportSectionLayout {
    static func sections(hidden: Set<ImportSection> = []) -> [ImportSection] {
        ImportSection.allCases.filter { !hidden.contains($0) }
    }
}

enum AboutBubble {
    /// Read by the settings function immediately after 「IN/OUT について」.
    static let body = "シフトはカレンダーアプリに、やることはリマインダーに保存します。iCloud を使っていれば、Apple がほかの端末と同期します。勤務先や設定はこの端末の中だけに保存し、サーバーへは送りません。広告の表示、地図の表示、所要時間の計算（現在地と勤務先の位置を Apple のマップサービスに送ります）、新しいバージョンの確認（App Store の公開情報を読みます）、Google マップのリンクからの勤務先の読み込み（リンク先と Apple のマップサービスに店名と位置を問い合わせます）では通信します。金額はすべて概算です。"
}

struct SpeechTail: Shape {
    var cornerRadius: CGFloat
    var tailWidth: CGFloat = 14
    var tailHeight: CGFloat = 10

    func path(in rect: CGRect) -> Path {
        let body = CGRect(x: 0, y: 0, width: rect.width, height: max(0, rect.height - tailHeight))
        var path = Path(roundedRect: body, cornerRadius: min(cornerRadius, body.height / 2))
        let tipX = min(max(28, cornerRadius), rect.width - cornerRadius)
        path.move(to: CGPoint(x: tipX - tailWidth / 2, y: body.maxY))
        path.addLine(to: CGPoint(x: tipX, y: rect.maxY))
        path.addLine(to: CGPoint(x: tipX + tailWidth / 2, y: body.maxY))
        path.closeSubpath()
        return path
    }
}
