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
        let read = WorkplaceRead.draft(fromMapsLink: link)
        draft = read
        notice = ""
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
        let text = await WorkplaceImageRead.transcript(from: data)
        var read = WorkplaceRead.draft(from: text)
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            read.mapsNotice = "画像から文字を見つけられませんでした。店名や住所を直接入力してください。"
        }
        draft = read
        working = false
    }
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
    @State private var showTranscript = false

    init(draft: WorkplaceDraft, onApply: @escaping (WorkplaceDraft) -> Void, onBack: @escaping () -> Void) {
        _draft = State(initialValue: draft)
        self.onApply = onApply
        self.onBack = onBack
    }

    var body: some View {
        ScreenScroll {
            if !draft.mapsNotice.isEmpty {
                Text(draft.mapsNotice)
                    .designFont(13)
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            field("名前", text: $draft.name, choices: draft.nameChoices, open: $showNames)
            field("電話番号", text: $draft.phone, choices: draft.phoneChoices, open: $showPhones)
            field("住所", text: $draft.address, choices: draft.addressChoices, open: $showAddresses)
            field("営業時間", text: $draft.hours, choices: draft.hoursChoices, open: $showHours)
            field("公式URL", text: $draft.officialURL, choices: draft.urlChoices, open: $showURLs)
            Toggle("住所から勤務先の位置を設定", isOn: $draft.locateFromAddress)
                .designFont(16, weight: .bold)
                .tint(Theme.lime)
                .padding(.top, 8)
            Text("オンにすると「反映」を押したときに住所を Apple のマップサービスに送り、位置を探します。住所は勤務先に保存します。位置はあとから地図で直せます。")
                .designFont(13)
                .foregroundStyle(Theme.muted)
            DisclosureGroup("読み取った文字", isExpanded: $showTranscript) {
                Text(draft.transcript.isEmpty ? "文字はありません。" : draft.transcript)
                    .designFont(13)
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .designFont(16, weight: .bold)
            .tint(Theme.ink)
            .padding(.top, 8)
            if working {
                ProgressView().tint(Theme.lime).frame(maxWidth: .infinity).padding(.top, 16)
            } else {
                LimeCapsuleButton(title: "反映", fillWidth: true, designSize: 16) {
                    Task { await apply() }
                }
                .padding(.top, 16)
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
                Button("反映") { Task { await apply() } }
                    .foregroundStyle(Theme.ink)
                    .disabled(working)
            }
        }
        .darkSheet()
    }

    private func field(_ title: String, text: Binding<String>, choices: [String], open: Binding<Bool>) -> some View {
        let extras = choices.filter { $0 != text.wrappedValue }
        return VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .designFont(13, weight: .bold)
            TextField(title, text: text)
                .designFont(16)
                .padding(14)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            if !extras.isEmpty {
                DisclosureGroup("ほかの候補", isExpanded: open) {
                    ForEach(extras, id: \.self) { choice in
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

    private func apply() async {
        working = true
        var copy = draft
        if copy.locateFromAddress {
            let address = copy.address.trimmingCharacters(in: .whitespacesAndNewlines)
            if let coordinate = await WorkplaceLocator.coordinate(for: address) {
                copy.latitude = coordinate.latitude
                copy.longitude = coordinate.longitude
                copy.hasCoordinate = true
            } else {
                copy.hasCoordinate = false
            }
        } else {
            copy.hasCoordinate = false
        }
        draft = copy
        working = false
        onApply(copy)
    }
}
