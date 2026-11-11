import AppIntents
import Foundation
import SwiftData

enum MonthForecastMath {
    static func yen(days: [(date: Date, yen: Int)], now: Date, calendar: Calendar = .current) -> Int {
        guard let interval = IncomeEngine.monthInterval(now, calendar: calendar) else { return 0 }
        return days.reduce(0) { sum, row in
            let day = calendar.startOfDay(for: row.date)
            guard day >= interval.0, day < interval.1 else { return sum }
            return sum + row.yen
        }
    }
}

@MainActor
enum WorkplaceActions {
    private static var context: ModelContext { AppModel.container.mainContext }

    static func allWorkplaces() -> [Workplace] {
        (try? context.fetch(FetchDescriptor<Workplace>())) ?? []
    }

    static func entities() -> [WorkplaceEntity] {
        allWorkplaces().map { WorkplaceEntity(id: $0.uuid, name: $0.name) }
    }

    static func entities(for identifiers: [UUID]) -> [WorkplaceEntity] {
        let wanted = Set(identifiers)
        return entities().filter { wanted.contains($0.id) }
    }

    @discardableResult
    static func insert(draft: WorkplaceDraft) -> String {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "名前がないので、勤務先は作っていません。" }
        let settings = (try? context.fetch(FetchDescriptor<AppSettings>()))?.first
        let rows = allWorkplaces()
        let used = Set(rows.map(\.colorHex))
        let color = Theme.palette.first { !used.contains($0) } ?? Theme.palette[rows.count % Theme.palette.count]
        let workplace = Workplace(
            name: name,
            colorHex: color,
            hourlyWage: settings?.defaultHourlyWage ?? 1200,
            transportAllowance: settings?.defaultTransportAllowance ?? 500,
            notes: draft.phone
        )
        apply(draft, to: workplace)
        context.insert(workplace)
        try? context.save()
        return "\(name)を勤務先に追加しました。"
    }

    static func apply(_ draft: WorkplaceDraft, to workplace: Workplace) {
        if !draft.address.isEmpty { workplace.place = draft.address }
        if !draft.phone.isEmpty {
            workplace.phone = draft.phone
            if workplace.notes.isEmpty { workplace.notes = draft.phone }
        }
        if !draft.hours.isEmpty { workplace.openingHours = draft.hours }
        if !draft.officialURL.isEmpty { workplace.officialURL = draft.officialURL }
        if draft.hasCoordinate {
            workplace.latitude = draft.latitude
            workplace.longitude = draft.longitude
            workplace.hasMapCoordinate = true
        }
    }

    static func addShift(workplaceID: UUID, date: Date, start: Date, end: Date) -> String {
        guard let workplace = allWorkplaces().first(where: { $0.uuid == workplaceID }) else {
            return "勤務先が見つかりません。"
        }
        let calendar = ShiftOverlap.tokyo
        let day = calendar.startOfDay(for: date)
        let startMinutes = ShiftDatePolicy.clockMinutes(from: start, calendar: calendar)
        let endMinutes = ShiftDatePolicy.clockMinutes(from: end, calendar: calendar)
        guard startMinutes != endMinutes else {
            return "開始と終了が同じです。保存できません。"
        }
        let shifts = (try? context.fetch(FetchDescriptor<WorkShift>())) ?? []
        let travel = UserDefaults.standard.integer(forKey: "settings.travelMinutes")
        let travelMinutes = UserDefaults.standard.object(forKey: "settings.travelMinutes") == nil ? 30 : travel
        let proposed = ShiftOverlap.span(
            id: "new",
            name: workplace.name,
            workplace: workplace.uuid,
            day: day,
            start: startMinutes,
            end: endMinutes,
            calendar: calendar
        )
        let found = ShiftOverlap.conflicts(
            of: proposed,
            among: shifts.map { ShiftOverlap.span(from: $0, calendar: calendar) },
            travelMinutes: travelMinutes,
            calendar: calendar
        )
        if !found.isEmpty {
            return "このシフトは確認が必要です。アプリで確認してから保存してください。"
        }
        let follows = !workplace.payIsDaily
        let breakMinutes = follows
            ? BreakRules.automaticMinutes(start: startMinutes, end: endMinutes, customBreaks: workplace.customBreaks, rules: workplace.breakRules)
            : 0
        context.insert(WorkShift(
            date: day,
            startMinutes: startMinutes,
            endMinutes: endMinutes,
            breakMinutes: breakMinutes,
            breakFollowsRules: follows,
            workplace: workplace
        ))
        try? context.save()
        return "\(workplace.name)のシフトを追加しました。"
    }

    static func clockIn(workplaceID: UUID?) -> String {
        let today = todays(workplaceID)
        guard !today.isEmpty else {
            return "今日のシフトが見つかりません。先にシフトを追加してください。"
        }
        guard let shift = today.first(where: { $0.clockedInAt == nil }) else {
            return "このシフトはすでに出勤済みです。"
        }
        shift.clockedInAt = .now
        try? context.save()
        return "\(shift.workplace?.name ?? "シフト")に出勤しました。予定の時刻と給料は変えていません。"
    }

    static func clockOut(workplaceID: UUID?) -> String {
        let shifts = (try? context.fetch(FetchDescriptor<WorkShift>())) ?? []
        let today = shifts.filter { Calendar.current.isDateInToday($0.date) }
        let match = today.first { shift in
            shift.clockedInAt != nil && shift.clockedOutAt == nil && (workplaceID == nil || shift.workplace?.uuid == workplaceID)
        }
        guard let match else {
            return "出勤中のシフトが見つかりません。"
        }
        match.clockedOutAt = .now
        try? context.save()
        return "\(match.workplace?.name ?? "シフト")を退勤しました。予定の時刻と給料は変えていません。"
    }

    static func monthForecast(now: Date = .now) -> Int {
        let include = ((try? context.fetch(FetchDescriptor<AppSettings>()))?.first?.includeTransport) ?? true
        let rows = ((try? context.fetch(FetchDescriptor<WorkShift>())) ?? []).map {
            (date: $0.date, yen: $0.estimatedYen(includeTransport: include))
        }
        return MonthForecastMath.yen(days: rows, now: now)
    }

    private static func todays(_ workplaceID: UUID?) -> [WorkShift] {
        let shifts = (try? context.fetch(FetchDescriptor<WorkShift>())) ?? []
        return shifts.filter { shift in
            Calendar.current.isDateInToday(shift.date) && (workplaceID == nil || shift.workplace?.uuid == workplaceID)
        }
    }
}

struct WorkplaceEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "勤務先")
    static var defaultQuery = WorkplaceEntityQuery()

    var id: UUID
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct WorkplaceEntityQuery: EntityQuery {
    func entities(for identifiers: [WorkplaceEntity.ID]) async throws -> [WorkplaceEntity] {
        await WorkplaceActions.entities(for: identifiers)
    }

    func suggestedEntities() async throws -> [WorkplaceEntity] {
        await WorkplaceActions.entities()
    }
}

struct WorkplaceDraftEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "勤務先の下書き")
    static var defaultQuery = WorkplaceDraftEntityQuery()

    var id: UUID
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name.isEmpty ? "勤務先の下書き" : name)")
    }
}

struct WorkplaceDraftEntityQuery: EntityQuery {
    func entities(for identifiers: [WorkplaceDraftEntity.ID]) async throws -> [WorkplaceDraftEntity] {
        var found: [WorkplaceDraftEntity] = []
        for id in identifiers {
            if let draft = await WorkplaceDraftStore.load(id: id) {
                found.append(WorkplaceDraftEntity(id: id, name: draft.name))
            }
        }
        return found
    }
}

struct CreateWorkplaceIntent: AppIntent {
    static var title: LocalizedStringResource = "勤務先を作る"
    static var description = IntentDescription("名前と住所から勤務先を追加します。保存済みのシフトは変えません。")
    static var openAppWhenRun = true

    @Parameter(title: "名前") var name: String
    @Parameter(title: "住所") var place: String?
    @Parameter(title: "電話番号") var phone: String?

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$name)を勤務先にする") {
            \.$place
            \.$phone
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        var draft = WorkplaceDraft()
        draft.name = name
        draft.address = place ?? ""
        draft.phone = phone ?? ""
        draft.locateFromAddress = false
        let message = WorkplaceActions.insert(draft: draft)
        return .result(dialog: "\(message)")
    }
}

struct AddShiftIntent: AppIntent {
    static var title: LocalizedStringResource = "シフトを追加"
    static var description = IntentDescription("勤務先と日付、開始と終了からシフトを追加します。重なりがあるときは保存しません。")
    static var openAppWhenRun = true

    @Parameter(title: "勤務先") var workplace: WorkplaceEntity
    @Parameter(title: "日付") var date: Date
    @Parameter(title: "開始") var start: Date
    @Parameter(title: "終了") var end: Date

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$workplace)に\(\.$date) \(\.$start)から\(\.$end)のシフトを追加")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = WorkplaceActions.addShift(workplaceID: workplace.id, date: date, start: start, end: end)
        return .result(dialog: "\(message)")
    }
}

struct ClockInIntent: AppIntent {
    static var title: LocalizedStringResource = "出勤"
    static var description = IntentDescription("今日のシフトに出勤の時刻を残します。予定の開始と給料は変えません。")
    static var openAppWhenRun = true

    @Parameter(title: "勤務先") var workplace: WorkplaceEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("出勤する") {
            \.$workplace
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = WorkplaceActions.clockIn(workplaceID: workplace?.id)
        return .result(dialog: "\(message)")
    }
}

struct ClockOutIntent: AppIntent {
    static var title: LocalizedStringResource = "退勤"
    static var description = IntentDescription("出勤中のシフトに退勤の時刻を残します。予定の終了と給料は変えません。")
    static var openAppWhenRun = true

    @Parameter(title: "勤務先") var workplace: WorkplaceEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("退勤する") {
            \.$workplace
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = WorkplaceActions.clockOut(workplaceID: workplace?.id)
        return .result(dialog: "\(message)")
    }
}

struct MonthForecastIntent: AppIntent {
    static var title: LocalizedStringResource = "今月の収入見込み"
    static var description = IntentDescription("今月のシフトから、給料の見込みを計算します。")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let yen = WorkplaceActions.monthForecast()
        return .result(dialog: "今月の収入見込みは\(yen)円です。")
    }
}

struct OpenWorkplaceDraftIntent: OpenIntent {
    static var title: LocalizedStringResource = "勤務先の下書きを開く"
    static var openAppWhenRun = true

    @Parameter(title: "下書き")
    var target: WorkplaceDraftEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        WorkplaceDraftRouter.shared.open(id: target.id)
        return .result()
    }
}

#if canImport(VisualIntelligence)
import CoreImage
import CoreVideo
import VisualIntelligence

@available(iOS 26.0, *)
struct WorkplaceSeenQuery: IntentValueQuery {
    func values(for input: SemanticContentDescriptor) async throws -> [WorkplaceDraftEntity] {
        guard let pixelBuffer = input.pixelBuffer else { return [] }
        // The device SDK types this buffer as read-only. The simulator SDK
        // still exposes a CVPixelBuffer. Both paths keep the same image.
        #if targetEnvironment(simulator)
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        #else
        let image = pixelBuffer.withUnsafeBuffer { CIImage(cvPixelBuffer: $0) }
        #endif
        guard let cgImage = CIContext().createCGImage(image, from: image.extent) else { return [] }
        let text = await WorkplaceImageRead.transcript(from: cgImage)
        let draft = WorkplaceRead.draft(from: text)
        guard !draft.name.isEmpty || !draft.address.isEmpty || !draft.phone.isEmpty else { return [] }
        let id = UUID()
        await WorkplaceDraftStore.save(draft, id: id)
        return [WorkplaceDraftEntity(id: id, name: draft.name.isEmpty ? draft.address : draft.name)]
    }
}
#endif
