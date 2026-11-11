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
        ScreenScroll {
            Text("ショップカードの写真か、Google マップでお店の「共有」からコピーしたリンク")
                .designFont(13)
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("ショップカード（写真）")
                .designFont(16, weight: .bold)
                .padding(.top, 8)
            HStack(spacing: 8) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    capsule("写真から選ぶ", systemImage: "photo")
                }
                .buttonStyle(.plain)
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button { showCamera = true } label: {
                        capsule("撮影する", systemImage: "camera")
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("Google マップのリンク")
                .designFont(16, weight: .bold)
                .padding(.top, 16)
            TextField("Google マップのリンクを貼り付け", text: $link)
                .designFont(16)
                .padding(14)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            Button("コピーしたリンクを貼る") {
                if let clip = UIPasteboard.general.string { link = clip }
            }
            .designFont(16, weight: .medium)
            .foregroundStyle(Theme.lime)
            .padding(.top, 4)
            if !notice.isEmpty {
                Text(notice)
                    .designFont(13)
                    .foregroundStyle(Theme.behind)
                    .padding(.top, 8)
            }
            if working {
                ProgressView().tint(Theme.lime).frame(maxWidth: .infinity).padding(.top, 12)
            } else {
                LimeCapsuleButton(title: "リンクを読み取る", fillWidth: true, designSize: 16) {
                    readLink()
                }
                .padding(.top, 12)
                .disabled(link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
            }
        }
        .background(Theme.background)
        .navigationTitle("取り込み")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("キャンセル") { dismiss() }
                    .foregroundStyle(Theme.ink)
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

    private func capsule(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(title)
        }
        .designFont(16, weight: .bold)
        .foregroundStyle(Theme.ink)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Theme.card)
        .clipShape(Capsule())
        .overlay { Capsule().stroke(Theme.ink, lineWidth: 1) }
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
        ScreenScroll {
            thumbnail
            if !draft.mapsNotice.isEmpty {
                Text(draft.mapsNotice)
                    .designFont(13)
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            field("名前", id: .name, text: text(\.name, \.nameNote), note: draft.nameNote, choicesOpen: $showNames)
            field("電話番号", id: .phone, text: text(\.phone, \.phoneNote), note: draft.phoneNote, choicesOpen: $showPhones)
            field("住所", id: .address, text: text(\.address, \.addressNote), note: draft.addressNote, choicesOpen: $showAddresses)
            locate
            field("営業時間", id: .hours, text: text(\.hours, \.hoursNote), note: draft.hoursNote, choicesOpen: $showHours)
            field("公式URL", id: .url, text: text(\.officialURL, \.urlNote), note: draft.urlNote, choicesOpen: $showURLs)
            if working {
                ProgressView().tint(Theme.lime).frame(maxWidth: .infinity).padding(.top, 16)
            } else {
                LimeCapsuleButton(title: "勤務先を追加", fillWidth: true, designSize: 16) {
                    Task { await apply() }
                }
                .padding(.top, 16)
                .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
            }
        }
        .background(Theme.background)
        .navigationTitle("読み取り結果")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("キャンセル") { onBack() }
                    .foregroundStyle(Theme.ink)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("勤務先を追加") { Task { await apply() } }
                    .foregroundStyle(Theme.ink)
                    .disabled(working || draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .darkSheet()
        .task {
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
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                        .stroke(active ? Theme.ink : Theme.muted, lineWidth: active ? 2 : 1)
                        .background(active ? Theme.lime.opacity(0.45) : Color.white.opacity(0.05))
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
        VStack(alignment: .leading, spacing: 8) {
            Toggle("住所から位置を探す", isOn: $draft.locateFromAddress)
                .designFont(16, weight: .bold)
                .tint(Theme.lime)
                .disabled(draft.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if draft.locateFromAddress, draft.hasCoordinate {
                let coordinate = CLLocationCoordinate2D(latitude: draft.latitude, longitude: draft.longitude)
                Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 500, longitudinalMeters: 500))) {
                    Marker(draft.locatedName.isEmpty ? "住所" : draft.locatedName, coordinate: coordinate)
                }
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .allowsHitTesting(false)
                if !draft.locatedName.isEmpty {
                    Text(draft.locatedName)
                        .designFont(13)
                        .foregroundStyle(Theme.ink)
                }
                if draft.namesDiffer {
                    Label("見つかった場所の名前が店名と違います", systemImage: "exclamationmark.triangle")
                        .designFont(13, weight: .bold)
                        .foregroundStyle(Theme.ink)
                }
            }
            Text("住所を Apple のマップサービスに送ります。位置の検索以外には使いません。")
                .designFont(13)
                .foregroundStyle(Theme.muted)
        }
        .padding(.top, 8)
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
                    .designFont(13, weight: .bold)
                if note.confidence == .review && !note.edited {
                    Label("要確認", systemImage: "exclamationmark.triangle")
                        .designFont(13, weight: .bold)
                        .foregroundStyle(Theme.ink)
                        .accessibilityLabel("要確認")
                }
            }
            TextField(title, text: text)
                .focused($focus, equals: id)
                .designFont(16)
                .padding(14)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            if note.confidence == .missing || text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("見つかりませんでした")
                    .designFont(13)
                    .foregroundStyle(Theme.muted)
            }
            if !note.edited, let origin = note.origin, !text.wrappedValue.isEmpty {
                Text(origin.footnote)
                    .designFont(13)
                    .foregroundStyle(Theme.muted)
            }
            if !extras.isEmpty {
                DisclosureGroup("候補が\(extras.count)件", isExpanded: choicesOpen) {
                    ForEach(Array(extras), id: \.self) { choice in
                        Button(choice) { text.wrappedValue = choice }
                            .designFont(16)
                            .foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .designFont(13, weight: .medium)
                .tint(Theme.muted)
            }
        }
        .padding(.top, 8)
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
