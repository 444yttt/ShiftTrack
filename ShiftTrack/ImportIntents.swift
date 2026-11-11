import AppIntents
import UniformTypeIdentifiers

struct ImportShiftTextIntent: AppIntent {
    static var title: LocalizedStringResource = "シフト表のテキストを取り込む"
    static var description = IntentDescription("貼り付けたシフト表から勤務の候補を作ります。保存前にアプリで確認します。処理は端末内で行い、サーバーには送りません。")
    static var openAppWhenRun = true

    @Parameter(title: "シフト表のテキスト", requestValueDialog: IntentDialog("シフト表の内容を教えてください"))
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("「\(\.$text)」からシフトを取り込む")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let names = await WorkplaceLookup.names()
        let pending = await ShiftExtractionService.extract(text: text, knownNames: names, fromImage: false)
        PendingImportStore.save(pending)
        if pending.candidates.isEmpty {
            return .result(dialog: "シフトを見つけられませんでした。アプリでテキストを確認できます。")
        }
        return .result(dialog: "\(pending.candidates.count)件の候補を作りました。アプリで確認して保存してください。")
    }
}

@available(iOS 18.0, *)
struct ImportShiftImageIntent: AppIntent {
    static var title: LocalizedStringResource = "シフト表の画像を取り込む"
    static var description = IntentDescription("シフト表の画像から勤務の候補を作ります。画像は端末内で読み、サーバーには送りません。")
    static var openAppWhenRun = true

    @Parameter(title: "シフト表の画像", supportedContentTypes: [.image])
    var image: IntentFile

    static var parameterSummary: some ParameterSummary {
        Summary("画像からシフトを取り込む")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let data = try await image.data
        let names = await WorkplaceLookup.names()
        let pending = await ShiftExtractionService.extract(imageData: data, knownNames: names)
        PendingImportStore.save(pending)
        if pending.candidates.isEmpty {
            return .result(dialog: "画像からシフトを見つけられませんでした。アプリで別の画像かテキストを試せます。")
        }
        return .result(dialog: "\(pending.candidates.count)件の候補を作りました。アプリで確認して保存してください。")
    }
}

struct ShiftTrackShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ImportShiftTextIntent(),
            phrases: [
                "\(.applicationName)でシフト表を取り込む",
                "\(.applicationName)にシフト表を読み込んで"
            ],
            shortTitle: "シフト表を取り込む",
            systemImageName: "text.viewfinder"
        )
        AppShortcut(
            intent: ClockInIntent(),
            phrases: ["\(.applicationName)で出勤"],
            shortTitle: "出勤",
            systemImageName: "figure.walk.arrival"
        )
        AppShortcut(
            intent: ClockOutIntent(),
            phrases: ["\(.applicationName)で退勤"],
            shortTitle: "退勤",
            systemImageName: "figure.walk.departure"
        )
        AppShortcut(
            intent: MonthForecastIntent(),
            phrases: [
                "\(.applicationName)で今月の見込み",
                "\(.applicationName)の今月の収入"
            ],
            shortTitle: "今月の見込み",
            systemImageName: "yensign.circle"
        )
    }
}
