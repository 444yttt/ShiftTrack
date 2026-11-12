import SwiftData
import SwiftUI

enum FirstRun {
    static let key = "shifttrack.onboardingDone"

    static func shouldShow(hasContent: Bool, defaults: UserDefaults = .standard) -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-UITestingReset") || arguments.contains("-UITestingSample") {
            return false
        }
        if defaults.bool(forKey: key) { return false }
        if hasContent {
            defaults.set(true, forKey: key)
            return false
        }
        return true
    }

    static func finish(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: key)
    }
}

struct OnboardingScreen: View {
    var onFinish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0
    @State private var showWizard = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("\(page + 1)/3")
                    .designFont(13, weight: .bold)
                    .foregroundStyle(Theme.muted)
                Spacer()
                Button("スキップ", action: onFinish)
                    .designFont(16, weight: .bold)
                    .foregroundStyle(Theme.ink)
            }
            Group {
                switch page {
                case 0:
                    pageCopy(
                        title: "シフトを、この端末に残す",
                        body: "勤務の時間と、その日の給与の見込みをまとめます。金額は概算です。"
                    )
                case 1:
                    pageCopy(
                        title: "勤務先を追加する",
                        body: "名前と時給があると、シフトの見込みが出ます。あとからでも追加できます。"
                    )
                    Button("勤務先を追加") { showWizard = true }
                        .buttonStyle(PressableStyle(large: true))
                        .designFont(16, weight: .bold)
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.lime)
                        .clipShape(Capsule())
                default:
                    pageCopy(
                        title: "必要なときだけ許可する",
                        body: "位置情報は、勤務先の住所を今いる場所から入れるときに使います。通知は、設定でオンにしたとき、開始の30分前と終了時刻にこの端末から知らせます。"
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Button(page == 2 ? "はじめる" : "次へ") {
                if page == 2 {
                    Task {
                        _ = await SettingsAccess.requestNotifications()
                        LocationPrompt.shared.request()
                        onFinish()
                    }
                } else {
                    changePage(page + 1)
                }
            }
            .buttonStyle(PressableStyle(large: true))
            .designFont(16, weight: .bold)
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Theme.ink)
            .clipShape(Capsule())
            .accessibilityIdentifier(page == 2 ? "onboarding.finish" : "onboarding.next")
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.background)
        .sheet(isPresented: $showWizard) {
            WorkplaceWizard()
        }
        .animation(reduceMotion ? nil : Motion.layout, value: showWizard)
    }

    private func pageCopy(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .designFont(28, weight: .black)
                .foregroundStyle(Theme.ink)
            Text(body)
                .designFont(16)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func changePage(_ next: Int) {
        if reduceMotion {
            page = next
        } else {
            withAnimation(Motion.settle) { page = next }
        }
    }
}
