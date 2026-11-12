import SwiftData
import SwiftUI
import UIKit

@main
struct ShiftTrackApp: App {
    init() {
        FontRegistry.ensureDoto()
        let paper = UIColor(
            red: CGFloat((ThemeHex.background >> 16) & 0xFF) / 255,
            green: CGFloat((ThemeHex.background >> 8) & 0xFF) / 255,
            blue: CGFloat(ThemeHex.background & 0xFF) / 255,
            alpha: 1
        )
        let ink = UIColor(
            red: CGFloat((ThemeHex.ink >> 16) & 0xFF) / 255,
            green: CGFloat((ThemeHex.ink >> 8) & 0xFF) / 255,
            blue: CGFloat(ThemeHex.ink & 0xFF) / 255,
            alpha: 1
        )
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = paper
        appearance.shadowColor = .clear
        appearance.titleTextAttributes = [.foregroundColor: ink]
        appearance.largeTitleTextAttributes = [.foregroundColor: ink]
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.locale, Locale(identifier: "ja_JP"))
                .preferredColorScheme(.light)
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
        ZStack {
            switch tab {
            case .list:
                TodayScreen().transition(.opacity)
            case .calendar:
                CalendarScreen().transition(.opacity)
            case .workplaces:
                WorkplaceDirectoryScreen().transition(.opacity)
            case .income:
                IncomeScreen().transition(.opacity)
            case .settings:
                SettingsScreen().transition(.opacity)
            }
        }
        // Screens own their side gutter (`ScreenScroll`). The old extra 20pt frame
        // here stacked with it and left only about 320pt of a 393pt screen.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            CustomTabBar(selection: $tab)
        }
        .topSafeAreaCover()
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
        .animation(Motion.allowed(Motion.layout, reduce: reduceMotion), value: tab)
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
        .preferredColorScheme(.light)
}
