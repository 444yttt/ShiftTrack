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
        .background(Theme.background)
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
        ScreenScroll {
            Text(IntelligenceAvailability.statusText)
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)

            if let imageData, let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.top, 12)
            }

            HStack(spacing: 8) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    label("写真を選ぶ", systemImage: "photo")
                }
                .buttonStyle(.plain)
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
                        showCamera = true
                    } label: {
                        label("撮影", systemImage: "camera")
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 12)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 160)
                    .padding(10)
                if text.isEmpty {
                    Text("11/7 カフェA 10:00-15:00\n11月8日 コンビニB 18:00-23:00")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.muted)
                        .padding(16)
                        .allowsHitTesting(false)
                }
            }
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.top, 12)

            Button {
                if let clip = UIPasteboard.general.string, !clip.isEmpty {
                    text = clip
                }
            } label: {
                Text("コピーした文字を貼る")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.lime)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)

            if !error.isEmpty {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.behind)
                    .padding(.top, 8)
            }

            if working {
                ProgressView()
                    .tint(Theme.lime)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 16)
            } else {
                LimeCapsuleButton(title: "読み取る", fillWidth: true) {
                    Task { await extract() }
                }
                .padding(.top, 16)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && imageData == nil)
                .opacity(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && imageData == nil ? 0.4 : 1)
            }
        }
        .background(Theme.background)
        .navigationTitle("シフト表を取り込む")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("閉じる") { dismiss() }
                    .foregroundStyle(Theme.lime)
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
            Text(title)
        }
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Theme.card)
        .clipShape(Capsule())
    }

    private func extract() async {
        working = true
        error = ""
        let names = workplaces.map(\.name)
        let pending: PendingImport
        if let imageData {
            pending = await ShiftExtractionService.extract(imageData: imageData, knownNames: names)
        } else {
            pending = await ShiftExtractionService.extract(text: text, knownNames: names, fromImage: false)
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
        ScreenScroll {
            Text(pending.message)
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)

            if pending.candidates.isEmpty {
                Text("候補がありません")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.top, 20)
            } else {
                VStack(spacing: 10) {
                    ForEach($pending.candidates) { $candidate in
                        candidateRow($candidate)
                    }
                }
                .padding(.top, 12)
            }

            if !savedNote.isEmpty {
                Text(savedNote)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.lime)
                    .padding(.top, 8)
            }

            LimeCapsuleButton(title: "選択した \(selectedCount) 件を保存", fillWidth: true) {
                save()
            }
            .padding(.top, 16)
            .disabled(selectedCount == 0)
            .opacity(selectedCount == 0 ? 0.4 : 1)

            Button("候補を破棄") {
                ImportRouter.shared.discard()
                dismiss()
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Theme.behind)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
        }
        .background(Theme.background)
        .navigationTitle("候補を確認")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("戻る") { onBack() }
                    .foregroundStyle(Theme.lime)
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
        HStack(alignment: .top, spacing: 12) {
            Button {
                candidate.wrappedValue.included.toggle()
            } label: {
                Image(systemName: candidate.wrappedValue.included ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(candidate.wrappedValue.included ? Theme.lime : Theme.muted)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 4) {
                Text(candidate.wrappedValue.workplaceName.isEmpty ? "勤務先未設定" : candidate.wrappedValue.workplaceName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                Text("\(Formatters.monthDayWeekday(candidate.wrappedValue.date))  \(Formatters.clock(candidate.wrappedValue.startMinutes))–\(Formatters.clock(candidate.wrappedValue.endMinutes))")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                Text(candidate.wrappedValue.createWorkplace ? "新規の勤務先として追加" : "既存の勤務先")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.lime)
            }
            Spacer()
            Button("編集") { editingID = candidate.wrappedValue.id }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.lime)
        }
        .padding(14)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
            guard PayMath.workedMinutes(
                start: candidate.startMinutes,
                end: candidate.endMinutes,
                breakMinutes: candidate.breakMinutes
            ) > 0 else { continue }
            let workplace = resolve(candidate, wage: wage, transport: transport, created: &created)
            guard let workplace else { continue }
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
                date: candidate.date,
                startMinutes: candidate.startMinutes,
                endMinutes: candidate.endMinutes,
                breakMinutes: candidate.breakMinutes,
                workplace: workplace
            )
            context.insert(shift)
            saved += 1
        }
        try? context.save()
        PendingImportStore.clear()
        ImportRouter.shared.refreshCount()
        savedNote = skipped > 0 ? "\(saved)件保存しました。同じシフト \(skipped)件は飛ばしました。" : "\(saved)件保存しました。"
        if saved > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                dismiss()
            }
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

    var body: some View {
        NavigationStack {
            ScreenScroll {
                VStack(alignment: .leading, spacing: 12) {
                    Text("勤務先")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.muted)
                    TextField("勤務先の名前", text: $candidate.workplaceName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                    Picker("登録方法", selection: $candidate.createWorkplace) {
                        Text("この名前で追加").tag(true)
                        Text("既存の勤務先").tag(false)
                    }
                    .pickerStyle(.segmented)
                    if !candidate.createWorkplace {
                        Picker("勤務先", selection: workplaceBinding) {
                            Text("選んでください").tag(Optional<UUID>.none)
                            ForEach(workplaces) { workplace in
                                Text(workplace.name).tag(Optional(workplace.uuid))
                            }
                        }
                        .tint(Theme.lime)
                    }
                    DatePicker("日付", selection: $candidate.date, displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "ja_JP"))
                    HStack {
                        VStack(alignment: .leading) {
                            Text("開始").font(.system(size: 12)).foregroundStyle(Theme.muted)
                            MinutesTimePicker(minutes: $candidate.startMinutes)
                        }
                        VStack(alignment: .leading) {
                            Text("終了").font(.system(size: 12)).foregroundStyle(Theme.muted)
                            MinutesTimePicker(minutes: $candidate.endMinutes)
                        }
                    }
                    Stepper(value: $candidate.breakMinutes, in: 0...480, step: 15) {
                        Text("休憩 \(candidate.breakMinutes)分")
                            .foregroundStyle(.white)
                    }
                    .tint(Theme.lime)
                }
                .padding(14)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .foregroundStyle(.white)
            }
            .background(Theme.background)
            .navigationTitle("候補を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                        .foregroundStyle(Theme.lime)
                }
            }
            .darkSheet()
        }
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

private struct PickedPhoto: Transferable {
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
