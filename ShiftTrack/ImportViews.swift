import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ImportFlowView: View {
    var startsInReview: Bool
    var pending: PendingImport?
    @State private var step: Step
    @State private var router = ImportRouter.shared

    init(startsInReview: Bool, pending: PendingImport?) {
        self.startsInReview = startsInReview
        self.pending = pending
        if startsInReview, let pending {
            _step = State(initialValue: .review(pending))
        } else {
            _step = State(initialValue: .chooser)
        }
    }

    enum Step {
        case chooser
        case review(PendingImport)
    }

    var body: some View {
        NavigationStack {
            switch step {
            case .chooser:
                ImportChooserView { pending in
                    step = .review(pending)
                }
            case .review(let pending):
                ImportReviewView(initial: pending) {
                    step = .chooser
                }
            }
        }
        .background(Theme.paper)
        .onDisappear { router.noteHandled() }
    }
}

struct ImportChooserView: View {
    var onExtracted: (PendingImport) -> Void
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Workplace.createdAt) private var workplaces: [Workplace]
    @State private var text = ""
    @State private var imageData: Data?
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var working = false
    @State private var error = ""

    var body: some View {
        ScreenScroll(spacing: Space.m) {
            InfoNote(text: IntelligenceAvailability.statusText)
                .padding(.top, Space.xs)
            SectionHeader(title: "写真から読む", detail: "シフト表の写真を選ぶか撮ります。文字はこの端末の中で読み取ります。")
            Card {
                if let imageData, let image = UIImage(data: imageData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 180)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                        .accessibilityLabel("選んだシフト表の画像")
                }
                HStack(spacing: Space.xs) {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        label("写真を選ぶ", systemImage: "photo")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("import.photo")
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button {
                            showCamera = true
                        } label: {
                            label("撮影する", systemImage: "camera")
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("import.camera")
                    }
                }
            }
            SectionHeader(title: "文字から読む", detail: "シフト表の文字を貼り付けるか、書きます。1行に1件です。")
            Card {
                Text("シフト表の文字")
                    .font(AppFont.label)
                    .foregroundStyle(Theme.ink)
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $text)
                        .font(AppFont.body)
                        .foregroundStyle(Theme.ink)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 160)
                        .padding(8)
                        .accessibilityLabel("シフト表の文字")
                        .accessibilityIdentifier("import.text")
                    if text.isEmpty {
                        Text(placeholder)
                            .font(AppFont.body)
                            .foregroundStyle(Theme.ink2)
                            .padding(14)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .background(Theme.sunken, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
                TextLinkButton(title: "コピーした文字を貼る", systemImage: "doc.on.clipboard", identifier: "import.paste") {
                    if let clip = UIPasteboard.general.string, !clip.isEmpty {
                        text = clip
                    }
                }
                if !assumption.isEmpty {
                    InfoNote(text: assumption)
                }
            }
            if !error.isEmpty {
                InfoNote(text: error, tone: .error)
            }
            if working {
                ProgressView("読み取っています…")
                    .tint(Theme.signalInk)
                    .frame(maxWidth: .infinity)
            } else {
                PrimaryButton(title: "読み取って候補を見る", identifier: "import.read") {
                    Task { await extract() }
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && imageData == nil)
            }
        }
        .background(Theme.paper)
        .navigationTitle("シフト表を取り込む")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("閉じる") { dismiss() }
                    .foregroundStyle(Theme.signalInk)
            }
        }
        .darkSheet()
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let photo = try? await item.loadTransferable(type: PickedPhoto.self) {
                    imageData = photo.data
                }
            }
        }
        .sheet(isPresented: $showCamera) {
            CameraPicker { data in
                imageData = data
            }
            .ignoresSafeArea()
        }
    }

    private func label(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .accessibilityHidden(true)
            Text(title)
        }
        .font(AppFont.label)
        .foregroundStyle(Theme.ink)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
    }

    private var placeholder: String {
        if ImportRouter.shared.defaultWorkplace.isEmpty {
            return "11/7 カフェA 10:00-15:00\n11月8日 コンビニB 18:00-23:00"
        }
        return "10:00-15:00\n18:00-23:00 休憩60分"
    }

    private var assumption: String {
        var lines: [String] = []
        if let day = ImportRouter.shared.fallbackDate {
            lines.append("日付の無い行は\(Formatters.longDay(day))として読みます。")
        }
        if !ImportRouter.shared.defaultWorkplace.isEmpty {
            lines.append("勤務先の無い行は「\(ImportRouter.shared.defaultWorkplace)」にします。")
        }
        lines.append("読み取ったあと、保存するとカレンダーに出ます。")
        return lines.joined()
    }

    private func extract() async {
        working = true
        error = ""
        let names = workplaces.map(\.name)
        let day = ImportRouter.shared.fallbackDate
        let workplace = ImportRouter.shared.defaultWorkplace
        let pending: PendingImport
        if let imageData {
            pending = await ShiftExtractionService.extract(
                imageData: imageData,
                knownNames: names,
                fallbackDate: day,
                defaultWorkplace: workplace
            )
        } else {
            pending = await ShiftExtractionService.extract(
                text: text,
                knownNames: names,
                fromImage: false,
                fallbackDate: day,
                defaultWorkplace: workplace
            )
        }
        PendingImportStore.save(pending)
        working = false
        if pending.candidates.isEmpty {
            error = pending.message
            return
        }
        onExtracted(pending)
    }
}

struct ImportReviewView: View {
    var onBack: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Workplace.createdAt) private var workplaces: [Workplace]
    @Query(sort: \WorkShift.date) private var shifts: [WorkShift]
    @Query private var settingsRows: [AppSettings]
    @State private var pending: PendingImport
    @State private var matched = false
    @State private var editingID: UUID?
    @State private var savedNote = ""

    init(initial: PendingImport, onBack: @escaping () -> Void) {
        self.onBack = onBack
        _pending = State(initialValue: initial)
    }

    var body: some View {
        ScreenScroll(spacing: Space.m) {
            InfoNote(text: pending.message)
                .padding(.top, Space.xs)
            if pending.candidates.isEmpty {
                EmptyState(systemImage: "doc.text.magnifyingglass", message: "候補がありません")
            } else {
                SectionHeader(title: "候補 \(pending.candidates.count)件", detail: "チェックを外した行は保存しません。行を押すと直せます。")
                ForEach($pending.candidates) { $candidate in
                    candidateRow($candidate)
                }
            }
            if !savedNote.isEmpty {
                InfoNote(text: savedNote, systemImage: "checkmark.circle")
            }
            PrimaryButton(title: "選んだ \(selectedCount) 件を保存", identifier: "import.save") {
                save()
            }
            .disabled(selectedCount == 0)
            DestructiveButton(title: "候補を捨てる", identifier: "import.discard") {
                ImportRouter.shared.discard()
                dismiss()
            }
        }
        .background(Theme.paper)
        .navigationTitle("候補を確認")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("戻る") { onBack() }
                    .foregroundStyle(Theme.signalInk)
            }
        }
        .darkSheet()
        .onAppear(perform: matchWorkplaces)
        .sheet(isPresented: Binding(
            get: { editingID != nil },
            set: { if !$0 { editingID = nil } }
        )) {
            if let editingID, let index = pending.candidates.firstIndex(where: { $0.id == editingID }) {
                CandidateEditor(candidate: $pending.candidates[index], workplaces: workplaces)
            }
        }
    }

    private var selectedCount: Int { pending.candidates.filter(\.included).count }

    private func candidateRow(_ candidate: Binding<ImportCandidate>) -> some View {
        let value = candidate.wrappedValue
        return HStack(alignment: .center, spacing: Space.s) {
            Button {
                candidate.wrappedValue.included.toggle()
            } label: {
                Image(systemName: value.included ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(value.included ? Theme.signalInk : Theme.ink2)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(value.included ? "保存する" : "保存しない")
            .accessibilityAddTraits(value.included ? [.isSelected, .isButton] : .isButton)
            Button {
                editingID = value.id
            } label: {
                HStack(spacing: Space.xs) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(value.workplaceName.isEmpty ? "勤務先が未設定" : value.workplaceName)
                            .font(AppFont.rowTitle)
                            .foregroundStyle(Theme.ink)
                        Text("\(Formatters.monthDayWeekday(value.date))  \(Formatters.clock(value.startMinutes))–\(Formatters.clock(value.endMinutes))  休憩\(value.breakMinutes)分\(value.breakFollowsRules ? "（決まりから）" : "")")
                            .font(AppFont.helper.monospacedDigit())
                            .foregroundStyle(Theme.ink2)
                        Text(value.createWorkplace ? "新しい勤務先として追加します" : "登録済みの勤務先に入れます")
                            .font(AppFont.helper.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                    }
                    Spacer(minLength: Space.xs)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Theme.ink2)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(RowButtonStyle())
            .accessibilityHint("押すと直せます")
        }
        .padding(Space.s)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    private func matchWorkplaces() {
        guard !matched else { return }
        for index in pending.candidates.indices {
            let name = normalize(pending.candidates[index].workplaceName)
            let match = workplaces.first { normalize($0.name) == name }
                ?? workplaces.first { workplace in
                    let existing = normalize(workplace.name)
                    return !name.isEmpty && (existing.contains(name) || name.contains(existing))
                }
            if let match {
                pending.candidates[index].workplaceID = match.uuid
                pending.candidates[index].createWorkplace = false
                pending.candidates[index].workplaceName = match.name
            } else {
                pending.candidates[index].createWorkplace = !pending.candidates[index].workplaceName.isEmpty
            }
            let rulePlace = pending.candidates[index].createWorkplace
                ? nil
                : workplaces.first { $0.uuid == pending.candidates[index].workplaceID }
            pending.candidates[index] = BreakRules.refreshed(pending.candidates[index], workplace: rulePlace)
        }
        matched = true
    }

    private func save() {
        let settings = settingsRows.first
        let wage = settings?.defaultHourlyWage ?? 1200
        let transport = settings?.defaultTransportAllowance ?? 500
        var created: [String: Workplace] = [:]
        var saved = 0
        var skipped = 0
        for candidate in pending.candidates where candidate.included {
            let workplace = resolve(candidate, wage: wage, transport: transport, created: &created)
            guard let workplace else { continue }
            let refreshed = BreakRules.refreshed(candidate, workplace: workplace)
            guard PayMath.workedMinutes(
                start: refreshed.startMinutes,
                end: refreshed.endMinutes,
                breakMinutes: refreshed.breakMinutes
            ) > 0 else { continue }
            let duplicate = shifts.contains { shift in
                shift.workplace?.uuid == workplace.uuid
                    && Calendar.current.isDate(shift.date, inSameDayAs: candidate.date)
                    && shift.startMinutes == candidate.startMinutes
                    && shift.endMinutes == candidate.endMinutes
            }
            if duplicate {
                skipped += 1
                continue
            }
            let shift = WorkShift(
                date: refreshed.date,
                startMinutes: refreshed.startMinutes,
                endMinutes: refreshed.endMinutes,
                breakMinutes: refreshed.breakMinutes,
                breakFollowsRules: refreshed.breakFollowsRules,
                workplace: workplace
            )
            context.insert(shift)
            saved += 1
        }
        do {
            try context.save()
        } catch {
            savedNote = "保存できませんでした。もう一度試してください。"
            return
        }
        PendingImportStore.clear()
        ImportRouter.shared.refreshCount()
        let focused = pending.candidates.filter(\.included).map(\.date)
        if saved > 0 || skipped > 0 {
            ImportRouter.shared.showSaved(dates: focused)
            savedNote = skipped > 0 ? "\(saved)件保存しました。同じシフト \(skipped)件は飛ばしました。" : "\(saved)件保存しました。"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                dismiss()
            }
        } else {
            savedNote = "保存できるシフトがありません。勤務先と開始・終了を確認してください。"
        }
    }

    private func resolve(
        _ candidate: ImportCandidate,
        wage: Int,
        transport: Int,
        created: inout [String: Workplace]
    ) -> Workplace? {
        if let id = candidate.workplaceID, let found = workplaces.first(where: { $0.uuid == id }), !candidate.createWorkplace {
            return found
        }
        let key = normalize(candidate.workplaceName)
        guard !key.isEmpty else { return nil }
        if let existing = created[key] { return existing }
        if let found = workplaces.first(where: { normalize($0.name) == key }) {
            created[key] = found
            return found
        }
        let used = Set(workplaces.map(\.colorHex) + created.values.map(\.colorHex))
        let color = Theme.palette.first { !used.contains($0) } ?? Theme.palette[(workplaces.count + created.count) % Theme.palette.count]
        let workplace = Workplace(
            name: candidate.workplaceName.trimmingCharacters(in: .whitespacesAndNewlines),
            colorHex: color,
            hourlyWage: wage,
            transportAllowance: transport,
            notes: "シフト表から追加"
        )
        context.insert(workplace)
        created[key] = workplace
        return workplace
    }

    private func normalize(_ text: String) -> String {
        TextNormalizer.fold(text).replacingOccurrences(of: " ", with: "").lowercased()
    }
}

struct CandidateEditor: View {
    @Binding var candidate: ImportCandidate
    var workplaces: [Workplace]
    @Environment(\.dismiss) private var dismiss
    @FocusState private var typing: Bool

    var body: some View {
        NavigationStack {
            ScreenScroll(spacing: Space.m) {
                Card {
                    LabeledField(label: "勤務先の名前", text: $candidate.workplaceName, prompt: "例：架空茶房 北窓", identifier: "candidate.name")
                    SegmentedRow(label: "入れ方", selection: $candidate.createWorkplace, identifier: "candidate.mode") {
                        Text("この名前で新しく追加").tag(true)
                        Text("登録済みから選ぶ").tag(false)
                    }
                    if !candidate.createWorkplace {
                        PickerRow(label: "勤務先", selection: workplaceBinding, identifier: "candidate.workplace") {
                            Text("選んでください").tag(Optional<UUID>.none)
                            ForEach(workplaces) { workplace in
                                Text(workplace.name).tag(Optional(workplace.uuid))
                            }
                        }
                    }
                }
                .padding(.top, Space.xs)
                Card {
                    DatePicker(selection: $candidate.date, displayedComponents: .date) {
                        Text("日付")
                            .font(AppFont.body)
                            .foregroundStyle(Theme.ink)
                    }
                    .environment(\.locale, Locale(identifier: "ja_JP"))
                    .tint(Theme.signalInk)
                    .frame(minHeight: 44)
                    HStack(alignment: .top, spacing: Space.xs) {
                        MinutesTimePicker(title: "開始", minutes: $candidate.startMinutes)
                        MinutesTimePicker(title: "終了", minutes: $candidate.endMinutes)
                    }
                    .onChange(of: candidate.startMinutes) { _, _ in refreshCandidateBreak() }
                    .onChange(of: candidate.endMinutes) { _, _ in refreshCandidateBreak() }
                }
                Card {
                    if ruleWorkplace?.payIsDaily == true {
                        InfoNote(text: "日給の勤務先では、休憩で給料は減りません。")
                    } else {
                        ToggleRow(
                            title: "勤務先の決まりで休憩を入れる",
                            helper: "オフにすると、下で選んだ休憩を使います。",
                            isOn: candidateBreakFollows,
                            identifier: "candidate.breakRules"
                        )
                        BreakMinutesControl(minutes: candidateBreakEntry, range: 0...600)
                    }
                    if PayMath.workedMinutes(
                        start: candidate.startMinutes,
                        end: candidate.endMinutes,
                        breakMinutes: candidate.breakMinutes
                    ) == 0 {
                        InfoNote(text: "働く時間が0分になるため、この行は保存されません。開始と終了を確かめてください。", tone: .error)
                    }
                }
            }
            .background(Theme.paper)
            .navigationTitle("候補を直す")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                        .foregroundStyle(Theme.signalInk)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("閉じる") {
                        typing = false
                        Keyboard.dismiss()
                    }
                    .foregroundStyle(Theme.signalInk)
                }
            }
            .darkSheet()
            .onChange(of: candidate.workplaceID) { _, _ in refreshCandidateBreak() }
            .onChange(of: candidate.createWorkplace) { _, _ in refreshCandidateBreak() }
        }
    }

    private var ruleWorkplace: Workplace? {
        guard !candidate.createWorkplace else { return nil }
        return workplaces.first { $0.uuid == candidate.workplaceID }
    }

    private var candidateBreakFollows: Binding<Bool> {
        Binding(
            get: { candidate.breakFollowsRules },
            set: { on in
                if on {
                    candidate.breakFollowsRules = true
                    refreshCandidateBreak()
                } else {
                    candidate.breakFollowsRules = false
                }
            }
        )
    }

    private var candidateBreakEntry: Binding<Int> {
        Binding(
            get: { candidate.breakMinutes },
            set: { newValue in
                candidate.breakFollowsRules = false
                candidate.breakMinutes = newValue
            }
        )
    }

    private func refreshCandidateBreak() {
        candidate = BreakRules.refreshed(candidate, workplace: ruleWorkplace)
    }

    private var workplaceBinding: Binding<UUID?> {
        Binding {
            candidate.workplaceID
        } set: { newValue in
            candidate.workplaceID = newValue
            if let newValue, let workplace = workplaces.first(where: { $0.uuid == newValue }) {
                candidate.workplaceName = workplace.name
            }
        }
    }
}

struct PickedPhoto: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            PickedPhoto(data: data)
        }
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.85) {
                parent.onImage(data)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
