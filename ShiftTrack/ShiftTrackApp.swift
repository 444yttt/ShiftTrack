import SwiftData
import SwiftUI
import UIKit

@main
struct ShiftTrackApp: App {
    init() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(red: 11 / 255, green: 11 / 255, blue: 11 / 255, alpha: 1)
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.locale, Locale(identifier: "ja_JP"))
                .preferredColorScheme(.dark)
                .tint(Theme.lime)
        }
        .modelContainer(AppModel.container)
    }
}

enum AppModel {
    static let container: ModelContainer = {
        let schema = Schema([Workplace.self, WorkShift.self, AppSettings.self, ShiftPattern.self, ShiftRequest.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: false)
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
    @State private var tab: AppTab = .today
    @State private var router = ImportRouter.shared

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
        .task {
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
        let schema = Schema([Workplace.self, WorkShift.self, AppSettings.self, ShiftPattern.self, ShiftRequest.self])
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
        .preferredColorScheme(.dark)
}
