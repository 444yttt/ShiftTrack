import SwiftData
import SwiftUI
import UIKit

@main
struct ShiftTrackApp: App {
    init() {
        FontRegistry.ensureDoto()
        let paper = Self.named("Paper", fallback: ThemeHex.background)
        let ink = Self.named("Ink", fallback: ThemeHex.ink)
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = paper
        appearance.shadowColor = .clear
        appearance.titleTextAttributes = [.foregroundColor: ink]
        appearance.largeTitleTextAttributes = [.foregroundColor: ink]
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance

        // The root uses the system tab bar. iOS 26 draws its own glass bar and
        // keeps the system item colours (selected = the app tint). Before iOS 26,
        // keep the default blurred background at every scroll position (the
        // transparent scroll-edge look let rows show through the labels) and
        // use readable item colours: the default grey is under 4.5:1 for the
        // small labels.
        if #unavailable(iOS 26.0) {
            let item = UITabBarItemAppearance()
            let muted = Self.named("Ink2", fallback: ThemeHex.muted)
            let accent = Self.named("SignalInk", fallback: ThemeHex.accentText)
            item.normal.iconColor = muted
            item.normal.titleTextAttributes = [.foregroundColor: muted]
            item.selected.iconColor = accent
            item.selected.titleTextAttributes = [.foregroundColor: accent]
            let tabBar = UITabBarAppearance()
            tabBar.configureWithDefaultBackground()
            tabBar.stackedLayoutAppearance = item
            tabBar.inlineLayoutAppearance = item
            tabBar.compactInlineLayoutAppearance = item
            UITabBar.appearance().standardAppearance = tabBar
            UITabBar.appearance().scrollEdgeAppearance = tabBar
        }
    }

    /// Named colours resolve per appearance. The fallback is the light hex.
    private static func named(_ name: String, fallback hex: UInt) -> UIColor {
        UIColor(named: name) ?? UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.locale, Locale(identifier: "ja_JP"))
                .tint(Theme.accentText)
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        }
        .modelContainer(AppModel.container)
    }
}

enum AppModel {
    static let container: ModelContainer = {
        let schema = Schema([Workplace.self, WorkShift.self, AppSettings.self, ShiftPattern.self, ShiftRequest.self, ShiftPart.self])
        // UI tests pass this so each launch starts empty. The on-disk store stays untouched.
        let arguments = ProcessInfo.processInfo.arguments
        let testing = arguments.contains("-UITestingReset") || arguments.contains("-UITestingSample")
        let configuration = ModelConfiguration(isStoredInMemoryOnly: testing)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("データを開けませんでした: \(error)")
        }
    }()
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \WorkShift.date) private var shifts: [WorkShift]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tab: AppTab = .list
    @State private var showOnboarding = false
    @State private var router = ImportRouter.shared
    @State private var draftRouter = WorkplaceDraftRouter.shared
    @State private var showLaunch = !ProcessInfo.processInfo.arguments.contains("-UITestingReset")
        && !ProcessInfo.processInfo.arguments.contains("-UITestingSample")

    var body: some View {
        // The standard tab bar, anchored to the bottom safe area. Each screen is a
        // scroll view, so its content scrolls under the bar and its last row can
        // still be scrolled clear of it.
        TabView(selection: $tab) {
            TodayScreen()
                .appTab(.list)
            CalendarScreen()
                .appTab(.calendar)
            IncomeScreen()
                .appTab(.income)
            WorkplaceDirectoryScreen()
                .appTab(.workplaces)
            SettingsScreen()
                .appTab(.settings)
        }
        .background {
            ShiftEndPulse()
        }
        .sheet(isPresented: $router.isPresented) {
            ImportFlowView(startsInReview: router.startInReview, pending: router.pending)
                .presentationBackground(Theme.background)
        }
        .sheet(isPresented: draftPresented) {
            if let id = draftRouter.presentedID, let draft = WorkplaceDraftStore.load(id: id) {
                NavigationStack {
                    WorkplaceReadResult(draft: draft) { applied in
                        _ = WorkplaceActions.insert(draft: applied)
                        draftRouter.presentedID = nil
                    } onBack: {
                        draftRouter.presentedID = nil
                    }
                }
                .presentationBackground(Theme.background)
            }
        }
        .overlay {
            if showLaunch {
                Color("LaunchBackground")
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .task {
            if showLaunch {
                switch LaunchCover.motion(returnFlag: LaunchCover.returnFlag()) {
                case .hold(let seconds):
                    try? await ContinuousClock().sleep(for: .seconds(seconds))
                    showLaunch = false
                case .spring(let response, let damping, let delay):
                    withAnimation(.spring(response: response, dampingFraction: damping).delay(delay)) {
                        showLaunch = false
                    }
                }
            }
            AppBootstrap.ensureSettings(in: context)
            SampleContent.install(in: context)
            ShiftTrackShortcuts.updateAppShortcutParameters()
            router.considerPending()
        }
        .overlay {
            if showOnboarding {
                OnboardingScreen {
                    FirstRun.finish()
                    showOnboarding = false
                }
                .transition(reduceMotion ? .opacity : .scale(scale: 0.98).combined(with: .opacity))
            }
        }
        .task {
            let placeCount = ((try? context.fetch(FetchDescriptor<Workplace>())) ?? []).count
            let shiftCount = ((try? context.fetch(FetchDescriptor<WorkShift>())) ?? []).count
            showOnboarding = FirstRun.shouldShow(hasContent: placeCount + shiftCount > 0)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                LaunchCover.markReturn()
            }
            if phase == .active {
                router.considerPending()
                let current = shifts
                Task {
                    await ShiftNoticeRefresh.apply(shifts: current)
                    await ShiftMirrorRefresh.apply(shifts: current)
                }
            }
        }
        .onChange(of: shiftFingerprint) { _, _ in
            let current = shifts
            Task {
                await ShiftNoticeRefresh.apply(shifts: current)
                await ShiftMirrorRefresh.apply(shifts: current)
            }
        }
    }

    private var shiftFingerprint: String {
        shifts.map {
            "\($0.uuid.uuidString)-\($0.startMinutes)-\($0.endMinutes)-\($0.date.timeIntervalSince1970)-\($0.todosRaw)"
        }.joined(separator: "|")
    }

    private var draftPresented: Binding<Bool> {
        Binding(
            get: { draftRouter.presentedID != nil },
            set: { if !$0 { draftRouter.presentedID = nil } }
        )
    }
}

enum AppBootstrap {
    @MainActor
    static func ensureSettings(in context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<AppSettings>())) ?? []
        guard existing.isEmpty else { return }
        context.insert(AppSettings())
        try? context.save()
    }
}

enum PreviewStore {
    @MainActor static let container: ModelContainer = {
        let schema = Schema([Workplace.self, WorkShift.self, AppSettings.self, ShiftPattern.self, ShiftRequest.self, ShiftPart.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [configuration])
        AppBootstrap.ensureSettings(in: container.mainContext)
        return container
    }()
}

#Preview {
    RootView()
        .modelContainer(PreviewStore.container)
        .environment(\.locale, Locale(identifier: "ja_JP"))
}
