import MapKit
import PhotosUI
import SwiftUI
import UIKit

struct WorkplaceImportView: View {
    var onApply: (WorkplaceDraft) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @State private var draft: WorkplaceDraft?
    @State private var working = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var notice = ""

    var body: some View {
        NavigationStack {
            if let draft {
                WorkplaceReadResult(draft: draft) { applied in
                    onApply(applied)
                    dismiss()
                } onBack: {
                    self.draft = nil
                }
            } else {
                chooser
            }
        }
        .background(Theme.background)
    }

    private var chooser: some View {
        ScreenScroll(spacing: Space.m) {
            InfoNote(text: "ショップカードの写真か、地図アプリでお店の「共有」からコピーしたリンクから、名前・住所・電話番号を読み取ります。読み取りはこの端末の中で行います。")
                .padding(.top, Space.xs)
            SectionHeader(title: "ショップカードの写真")
            Card {
                HStack(spacing: Space.xs) {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        sourceLabel("写真を選ぶ", systemImage: "photo")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("wimport.photo")
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button { showCamera = true } label: {
                            sourceLabel("撮影する", systemImage: "camera")
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("wimport.camera")
                    }
                }
            }
            SectionHeader(title: "地図のリンク")
            Card {
                LabeledField(label: "リンク", text: $link, prompt: "https://", keyboard: .URL, identifier: "wimport.link")
                TextLinkButton(title: "コピーしたリンクを貼る", systemImage: "doc.on.clipboard", identifier: "wimport.paste") {
                    if let clip = UIPasteboard.general.string { link = clip }
                }
                if working {
                    ProgressView("読み取っています…")
                        .tint(Theme.signalInk)
                        .frame(maxWidth: .infinity)
                } else {
                    PrimaryButton(title: "リンクを読み取る", identifier: "wimport.read") {
                        readLink()
                    }
                    .disabled(link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            if !notice.isEmpty {
                InfoNote(text: notice, tone: .error)
            }
        }
        .background(Theme.paper)
        .navigationTitle("写真・リンクから読む")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("キャンセル") { dismiss() }
                    .foregroundStyle(Theme.signalInk)
            }
        }
        .darkSheet()
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await readPhoto(item) }
        }
        .sheet(isPresented: $showCamera) {
            CameraPicker { data in
                Task { await readImage(data) }
            }
            .ignoresSafeArea()
        }
    }

    private func sourceLabel(_ title: String, systemImage: String) -> some View {
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

    private func readLink() {
        working = true
        notice = ""
        Task {
            draft = await WorkplaceMaps.read(link)
            working = false
        }
    }

    private func readPhoto(_ item: PhotosPickerItem) async {
        working = true
        notice = ""
        if let photo = try? await item.loadTransferable(type: PickedPhoto.self) {
            await readImage(photo.data)
        } else {
            notice = "写真を読めませんでした。"
            working = false
        }
    }

    private func readImage(_ data: Data) async {
        working = true
        draft = await WorkplaceImageRead.read(data: data)
        working = false
    }
}

private enum ReadFieldID: Hashable {
    case name, phone, address, hours, url
}

struct WorkplaceReadResult: View {
    @State private var draft: WorkplaceDraft
    var onApply: (WorkplaceDraft) -> Void
    var onBack: () -> Void
    @State private var working = false
    @State private var showNames = false
    @State private var showPhones = false
    @State private var showAddresses = false
    @State private var showHours = false
    @State private var showURLs = false
    @FocusState private var focus: ReadFieldID?

    init(draft: WorkplaceDraft, onApply: @escaping (WorkplaceDraft) -> Void, onBack: @escaping () -> Void) {
        _draft = State(initialValue: draft)
        self.onApply = onApply
        self.onBack = onBack
    }

    var body: some View {
        ScreenScroll(spacing: Space.m) {
            InfoNote(text: "読み取った結果です。違うところは直してから追加してください。画像の文字の枠を押すと、選んでいる欄に入ります。")
                .padding(.top, Space.xs)
            if draft.imageJPEG != nil || !draft.lines.isEmpty {
                SectionHeader(title: "読み取った文字")
                Card {
                    thumbnail
                    ForEach(draft.lines) { line in
                        Text(line.text)
                            .font(AppFont.helper)
                            .foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            if !draft.mapsNotice.isEmpty {
                InfoNote(text: draft.mapsNotice)
            }
            SectionHeader(title: "勤務先の情報")
            Card {
                field("名前", id: .name, text: text(\.name, \.nameNote), note: draft.nameNote, choicesOpen: $showNames)
                field("電話番号", id: .phone, text: text(\.phone, \.phoneNote), note: draft.phoneNote, choicesOpen: $showPhones)
                field("住所", id: .address, text: text(\.address, \.addressNote), note: draft.addressNote, choicesOpen: $showAddresses)
                locate
                field("営業時間", id: .hours, text: text(\.hours, \.hoursNote), note: draft.hoursNote, choicesOpen: $showHours)
                field("公式サイト", id: .url, text: text(\.officialURL, \.urlNote), note: draft.urlNote, choicesOpen: $showURLs)
            }
            InfoNote(text: "住所から位置を探すときだけ、住所を Apple のマップに送ります。ほかの用途には使いません。")
            if working {
                ProgressView("位置を確かめています…")
                    .tint(Theme.signalInk)
                    .frame(maxWidth: .infinity)
            } else {
                PrimaryButton(title: "この内容で入れる", identifier: "wimport.apply") {
                    Task { await apply() }
                }
                .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .background(Theme.paper)
        .navigationTitle("読み取った結果")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("戻る") { onBack() }
                    .foregroundStyle(Theme.signalInk)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("入れる") { Task { await apply() } }
                    .foregroundStyle(Theme.signalInk)
                    .disabled(working || draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .darkSheet()
        .task {
            if ImportReverseGeocode.shouldFill(current: draft.address, edited: draft.addressNote.edited),
               draft.hasCoordinate,
               let line = await ImportReverseGeocode.line(latitude: draft.latitude, longitude: draft.longitude) {
                draft.address = line
                draft.addressNote.origin = .map
                draft.addressNote.confidence = .review
            }
            if draft.locateFromAddress, !draft.hasCoordinate {
                await locate()
            }
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let data = draft.imageJPEG, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: 240)
                .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .overlay { boxes }
                .accessibilityLabel("読み取った画像")
        }
    }

    private var boxes: some View {
        GeometryReader { geo in
            ForEach(draft.lines.filter(\.hasBox)) { line in
                let rect = CGRect(
                    x: line.x * geo.size.width,
                    y: line.y * geo.size.height,
                    width: max(line.width * geo.size.width, 8),
                    height: max(line.height * geo.size.height, 8)
                )
                let active = highlighted.contains(line.id)
                Button {
                    use(line)
                } label: {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(active ? Theme.ink : Theme.ink2, lineWidth: active ? 2 : 1)
                        .background(active ? Theme.signal.opacity(0.45) : Color.white.opacity(0.05))
                }
                .buttonStyle(.plain)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .accessibilityLabel(line.text)
            }
        }
    }

    private var highlighted: Set<Int> {
        switch focus {
        case .name: return Set(draft.nameNote.lineIDs)
        case .phone: return Set(draft.phoneNote.lineIDs)
        case .address: return Set(draft.addressNote.lineIDs)
        case .hours: return Set(draft.hoursNote.lineIDs)
        case .url: return Set(draft.urlNote.lineIDs)
        case nil: return []
        }
    }

    private var locate: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            ToggleRow(
                title: "住所から位置を探す",
                helper: "見つかると、「地図」ボタンでその場所を開けます。",
                isOn: $draft.locateFromAddress,
                identifier: "wimport.locate"
            )
            .disabled(draft.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if draft.locateFromAddress, draft.hasCoordinate {
                let coordinate = CLLocationCoordinate2D(latitude: draft.latitude, longitude: draft.longitude)
                Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 500, longitudinalMeters: 500))) {
                    Marker(draft.locatedName.isEmpty ? "住所" : draft.locatedName, coordinate: coordinate)
                }
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .allowsHitTesting(false)
                .accessibilityLabel("見つかった場所の地図")
                if !draft.locatedName.isEmpty {
                    Text(draft.locatedName)
                        .font(AppFont.helper)
                        .foregroundStyle(Theme.ink)
                }
                if draft.namesDiffer {
                    InfoNote(text: "見つかった場所の名前が、店の名前と違います。住所を確かめてください。", tone: .warning)
                }
            }
        }
        .onChange(of: draft.locateFromAddress) { _, on in
            if on {
                Task { await locate() }
            } else {
                draft.hasCoordinate = false
                draft.locatedName = ""
            }
        }
        .onChange(of: draft.address) { _, address in
            if address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                draft.locateFromAddress = false
                draft.hasCoordinate = false
                draft.locatedName = ""
            }
        }
    }

    private func field(
        _ title: String,
        id: ReadFieldID,
        text: Binding<String>,
        note: FieldNote,
        choicesOpen: Binding<Bool>
    ) -> some View {
        let extras = note.choices.filter { $0 != text.wrappedValue }.prefix(3)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title)
                    .font(AppFont.label)
                    .foregroundStyle(Theme.ink)
                if note.confidence == .review && !note.edited {
                    StatusChip(text: "要確認", emphasized: true)
                        .accessibilityLabel("要確認")
                }
            }
            TextField(title, text: text)
                .focused($focus, equals: id)
                .font(AppFont.body)
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, Space.s)
                .frame(minHeight: 48)
                .background(Theme.sunken, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
                .accessibilityLabel(title)
            if note.confidence == .missing || text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                InfoNote(text: "見つかりませんでした。わかれば入れてください。")
            }
            if !note.edited, let origin = note.origin, !text.wrappedValue.isEmpty {
                InfoNote(text: origin.footnote)
            }
            if !extras.isEmpty {
                DisclosureGroup("ほかの候補 \(extras.count)件", isExpanded: choicesOpen) {
                    ForEach(Array(extras), id: \.self) { choice in
                        Button(choice) { text.wrappedValue = choice }
                            .font(AppFont.body)
                            .foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                }
                .font(AppFont.label)
                .tint(Theme.ink)
            }
        }
    }

    private func text(_ key: WritableKeyPath<WorkplaceDraft, String>, _ note: WritableKeyPath<WorkplaceDraft, FieldNote>) -> Binding<String> {
        Binding(
            get: { draft[keyPath: key] },
            set: { newValue in
                draft[keyPath: key] = newValue
                draft[keyPath: note].edited = true
                draft[keyPath: note].origin = nil
                let empty = newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                draft[keyPath: note].confidence = empty ? .missing : .high
            }
        )
    }

    private func use(_ line: ReadLine) {
        let value = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        switch focus ?? destination(for: value) {
        case .name: draft.name = value; mark(\.nameNote)
        case .phone: draft.phone = WorkplaceRead.validPhone(value) ?? value; mark(\.phoneNote)
        case .address: draft.address = value; mark(\.addressNote)
        case .hours: draft.hours = WorkplaceRead.hourValue(value) ?? value; mark(\.hoursNote)
        case .url: draft.officialURL = value; mark(\.urlNote)
        }
    }

    private func destination(for value: String) -> ReadFieldID {
        if WorkplaceRead.validPhone(value) != nil { return .phone }
        if WorkplaceRead.validAddress(value) != nil { return .address }
        if WorkplaceRead.hourValue(value) != nil { return .hours }
        if WorkplaceRead.urlClass(value) == .official { return .url }
        return .name
    }

    private func mark(_ note: WritableKeyPath<WorkplaceDraft, FieldNote>) {
        draft[keyPath: note].edited = true
        draft[keyPath: note].origin = nil
        draft[keyPath: note].confidence = .high
    }

    private func locate() async {
        let address = draft.address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty, let place = await WorkplaceLocator.locate(address: address) else {
            draft.hasCoordinate = false
            draft.locatedName = ""
            return
        }
        draft.latitude = place.latitude
        draft.longitude = place.longitude
        draft.hasCoordinate = true
        draft.locatedName = place.name
    }

    private func apply() async {
        working = true
        if draft.locateFromAddress {
            await locate()
        }
        working = false
        onApply(draft)
    }
}
