import SwiftUI

/// Redrawn stand-in for the reference wordmark. The IPA logo image is not bundled.
struct InOutWordmark: View {
    var body: some View {
        VStack(alignment: .leading, spacing: -4) {
            HStack(spacing: 1) {
                Text("i")
                Image(systemName: "arrow.down")
                    .font(.system(size: 11, weight: .black))
                Text("n")
                Image(systemName: "arrow.up")
                    .font(.system(size: 11, weight: .black))
            }
            HStack(spacing: 1) {
                Text("O")
                Image(systemName: "arrow.up")
                    .font(.system(size: 11, weight: .black))
                Text("UT")
            }
        }
        .font(.system(size: 22, weight: .black))
        .foregroundStyle(Theme.ink)
        .accessibilityLabel("しふとらっく")
    }
}

/// Sky stand-in. The reference JPEGs (TimeMorning, TimeDay, TimeNight) are not bundled.
struct DayIllustration: View {
    var hour: Int

    var body: some View {
        let night = hour < 6 || hour >= 18
        let morning = hour < 11
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: night
                    ? [Color(hex: 0x1B2A4A), Color(hex: 0x3D5A80)]
                    : morning
                        ? [Color(hex: 0x8FD3FF), Color(hex: 0xE8F7C8)]
                        : [Color(hex: 0x5EBEFF), Color(hex: 0xC6F24E)],
                startPoint: .top,
                endPoint: .bottom
            )
            Circle()
                .fill(night ? Color.white.opacity(0.85) : Color(hex: 0xFFF4C2))
                .frame(width: 36, height: 36)
                .offset(y: -48)
            Capsule()
                .fill(Color(hex: 0x3E8F4A))
                .frame(height: 28)
                .padding(.horizontal, 8)
        }
        .frame(height: 112)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityLabel("時間帯のイラストの代わり。元の画像は同梱していません。")
    }
}

/// Shop stand-in for the registration wizard. Not the original SetupWorkplace image.
struct ShopPlaceholder: View {
    var body: some View {
        ZStack {
            Color(hex: 0xF7F4EE)
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Theme.ink)
                    .frame(width: 120, height: 14)
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white)
                    .frame(width: 140, height: 64)
                    .overlay(alignment: .leading) {
                        Circle().fill(Color(hex: 0x3E8F4A)).frame(width: 16, height: 16).padding(10)
                    }
                Text("店舗イラストの代わり")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }
        }
        .frame(height: 160)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityLabel("店舗イラストの代わり。元の画像は同梱していません。")
    }
}

struct CalendarPlaceholder: View {
    var body: some View {
        ZStack {
            Color(hex: 0xF7F4EE)
            HStack(spacing: 16) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white)
                    .frame(width: 90, height: 70)
                    .overlay {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Theme.lime)
                            .frame(width: 28, height: 8)
                    }
                Circle()
                    .stroke(Theme.ink, lineWidth: 6)
                    .frame(width: 48, height: 48)
            }
        }
        .frame(height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityLabel("カレンダーイラストの代わり。元の画像は同梱していません。")
    }
}

struct GuideCard: View {
    var page: Int
    var total: Int
    var text: String
    var onBack: (() -> Void)?
    var onNext: () -> Void
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("\(page)/\(total)")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                }
                .accessibilityLabel("閉じる")
            }
            Text(text)
                .font(.system(size: 15))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                if let onBack {
                    Button("戻る", action: onBack)
                        .font(.system(size: 16, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white)
                        .clipShape(Capsule())
                        .overlay { Capsule().stroke(Theme.ink, lineWidth: 1.5) }
                }
                Button(page == total ? "おわり" : "次へ", action: onNext)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.ink)
                    .clipShape(Capsule())
            }
            .foregroundStyle(Theme.ink)
        }
        .padding(18)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
        .padding(.horizontal, 22)
        .accessibilityIdentifier("guide.card")
    }
}

enum GuideCopy {
    /// Wording read from the reference screenshots. Not every tutorial frame is included.
    static let today = [
        "今週の日付です。押すとその日のシフトを下に出します。左右の矢印か横にスワイプで、前後の週に移れます。黒い丸はシフトのある日です。",
        "今日の日付と今の時刻です。",
        "選んだ日のシフトです。勤務先、時間、始まりや終わりまでの時間が出ます。勤務中は、いま稼いだお給料が数字で増えていきます。「編集」でその日のシフトを直せます。",
        "選んだ日にシフトを追加します。",
        "その日のやることです。丸を押すと完了になり、リマインダーにも反映します。",
        "今日と今月のお給料の見込みです。シフトの時間と時給から計算します。"
    ]
    static let calendar = [
        "日付を押すと、その日の予定が時間の流れで見られます。シフトはパターンの色の丸で出ます。赤い「！」は、時間の重なりや移動時間の不足がある日です。"
    ]
    static let workplaces = [
        "マップで道順を見る、電話する、遅刻の連絡を送る、のボタンです。"
    ]
    static let settings = [
        "遅刻の連絡の文章を、勤務先ごとに直せます。"
    ]
}

enum GuideMemory {
    static func seen(_ key: String) -> Bool {
        UserDefaults.standard.bool(forKey: "guide.\(key)")
    }

    static func mark(_ key: String) {
        UserDefaults.standard.set(true, forKey: "guide.\(key)")
    }

    static var suppressed: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITestingReset")
    }
}
