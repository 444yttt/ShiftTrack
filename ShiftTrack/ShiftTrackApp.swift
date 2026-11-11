import SwiftData
import SwiftUI
import UIKit

@main
struct ShiftTrackApp: App {
    init() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(red: 243 / 255, green: 241 / 255, blue: 236 / 255, alpha: 1)
        appearance.titleTextAttributes = [.foregroundColor: UIColor.black]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.black]
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.locale, Locale(identifier: "ja_JP"))
                .preferredColorScheme(.light)
                .tint(Theme.lime)
        }
        .modelContainer(AppModel.container)
    }
}

enum AppModel {
    static let container: ModelContainer = {
        let schema = Schema([Workplace.self, WorkShift.self, AppSettings.self, ShiftPattern.self, ShiftRequest.self, ShiftPart.self])
        // UI tests pass this so each launch starts empty. The on-disk store stays untouched.
        let testing = ProcessInfo.processInfo.arguments.contains("-UITestingReset")
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
    @State private var tab: AppTab = .list
    @State private var router = ImportRouter.shared
    @State private var draftRouter = WorkplaceDraftRouter.shared
    @State private var showLaunch = !ProcessInfo.processInfo.arguments.contains("-UITestingReset")

    var body: some View {
        Group {
            switch tab {
            case .list:
                TodayScreen()
            case .calendar:
                CalendarScreen()
            case .workplaces:
                WorkplaceDirectoryScreen()
            case .income:
                IncomeScreen()
            case .settings:
                SettingsScreen()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(ScreenInsets.rootWide)
        .background(Theme.background)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            CustomTabBar(selection: $tab)
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
            ShiftTrackShortcuts.updateAppShortcutParameters()
            router.considerPending()
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
