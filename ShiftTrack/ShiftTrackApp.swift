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
    @State private var tab: AppTab = .list
    @State private var router = ImportRouter.shared
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
        .background(Theme.background)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            CustomTabBar(selection: $tab)
        }
        .sheet(isPresented: $router.isPresented) {
            ImportFlowView(startsInReview: router.startInReview, pending: router.pending)
                .presentationBackground(Theme.background)
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
                withAnimation(.easeOut(duration: 0.35)) {
                    showLaunch = false
                }
            }
            AppBootstrap.ensureSettings(in: context)
            ShiftTrackShortcuts.updateAppShortcutParameters()
            router.considerPending()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                router.considerPending()
            }
        }
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
