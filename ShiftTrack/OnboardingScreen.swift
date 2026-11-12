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

/// First launch: three short pages. Permissions are not requested here; each
/// one is asked for when the person turns its setting on.
struct OnboardingScreen: View {
    var onFinish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0
    @State private var showWizard = false

    private let pageCount = 3

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack {
                Text("\(page + 1) / \(pageCount)")
                    .font(AppFont.label.monospacedDigit())
                    .foregroundStyle(Theme.ink2)
                    .accessibilityLabel("\(pageCount)ページ中\(page + 1)ページ目")
                Spacer()
                Button("スキップ", action: onFinish)
                    .font(AppFont.label)
                    .foregroundStyle(Theme.signalInk)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("onboarding.skip")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    switch page {
                    case 0:
                        LandscapeView(date: .now)
                            .frame(height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.hero, style: .continuous))
                        pageCopy(
                            title: "シフトと給料を、ひと目で",
                            body: "勤務先とシフトを入れると、ホームに今日の予定と、勤務中の「いままでの稼ぎ」が出ます。金額は時給と設定から出した目安です。"
                        )
                    case 1:
                        symbolHero("building.2.fill")
                        pageCopy(
                            title: "まず勤務先を登録",
                            body: "名前と時給があれば始められます。住所と電話番号も入れておくと、ホームから地図・電話・メッセージがすぐ使えます。"
                        )
                        SecondaryButton(title: "いま勤務先を登録する", systemImage: "plus", identifier: "onboarding.workplace") {
                            showWizard = true
                        }
                    default:
                        symbolHero("hand.raised.fill")
                        pageCopy(
                            title: "許可は、使うときだけ",
                            body: "通知はシフトの前と終わりに、位置情報は住所を今いる場所から入れるときだけ使います。どちらも設定でオンにしたときに許可を求めます。記録はこの端末の中だけに残ります。"
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            pageDots
            PrimaryButton(title: page == pageCount - 1 ? "はじめる" : "次へ", identifier: page == pageCount - 1 ? "onboarding.finish" : "onboarding.next") {
                if page == pageCount - 1 {
                    onFinish()
                } else {
                    changePage(page + 1)
                }
            }
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.paper)
        .sheet(isPresented: $showWizard) {
            WorkplaceWizard()
        }
    }

    private var pageDots: some View {
        HStack(spacing: Space.xs) {
            ForEach(0..<pageCount, id: \.self) { index in
                Capsule()
                    .fill(index == page ? Theme.ink : Theme.stroke)
                    .frame(width: index == page ? 24 : 8, height: 8)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private func symbolHero(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 44, weight: .semibold))
            .foregroundStyle(Theme.onSignal)
            .frame(width: 104, height: 104)
            .background(Theme.signal, in: Circle())
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.l)
            .accessibilityHidden(true)
    }

    private func pageCopy(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(title)
                .font(.title.weight(.bold))
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            Text(body)
                .font(AppFont.body)
                .foregroundStyle(Theme.ink)
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
