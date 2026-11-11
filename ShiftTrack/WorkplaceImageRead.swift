import CoreImage
import CoreLocation
import UIKit
import Vision

enum WorkplaceImageRead {
    static func transcript(from data: Data) async -> String {
        if #available(iOS 26.0, *) {
            if let text = try? await documentText(data), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
        }
        return (try? ShiftImageReader.recognizeText(in: data)) ?? ""
    }

    static func transcript(from image: CGImage) async -> String {
        guard let data = UIImage(cgImage: image).jpegData(compressionQuality: 0.85) else { return "" }
        return await transcript(from: data)
    }

    @available(iOS 26.0, *)
    private static func documentText(_ data: Data) async throws -> String {
        let request = RecognizeDocumentsRequest()
        let observations = try await request.perform(on: data, orientation: .up)
        guard let document = observations.first?.document else { return "" }
        return document.paragraphs
            .map(\.transcript)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
    }
}

enum WorkplaceLocator {
    static func coordinate(for address: String) async -> CLLocationCoordinate2D? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let marks = try? await CLGeocoder().geocodeAddressString(trimmed)
        return marks?.first?.location?.coordinate
    }
}

@MainActor
enum WorkplaceDraftStore {
    private static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ShiftTrack", isDirectory: true)
            .appendingPathComponent("workplace-drafts", isDirectory: true)
    }

    static func save(_ draft: WorkplaceDraft, id: UUID) {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(draft)
            try data.write(to: folder.appendingPathComponent(id.uuidString), options: .atomic)
        } catch {
            return
        }
    }

    static func load(id: UUID) -> WorkplaceDraft? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(id.uuidString)) else { return nil }
        return try? JSONDecoder().decode(WorkplaceDraft.self, from: data)
    }
}

@MainActor
@Observable
final class WorkplaceDraftRouter {
    static let shared = WorkplaceDraftRouter()
    var presentedID: UUID?

    func open(id: UUID) {
        presentedID = id
    }
}
