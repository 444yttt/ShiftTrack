import CoreLocation
import Foundation
import MapKit

struct LocatedPlace: Equatable {
    var latitude: Double
    var longitude: Double
    var name: String
    var phone: String
    var address: String
    var url: String
}

enum WorkplaceLocator {
    static func locate(address: String) async -> LocatedPlace? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if #available(iOS 26.0, *) {
            if let place = await mapKit(trimmed) { return place }
        }
        return await coreLocation(trimmed)
    }

    static func search(name: String, latitude: Double, longitude: Double) async -> LocatedPlace? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = name
        request.resultTypes = .pointOfInterest
        let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        request.region = MKCoordinateRegion(center: center, latitudinalMeters: 1000, longitudinalMeters: 1000)
        guard let response = try? await MKLocalSearch(request: request).start() else { return nil }
        let here = CLLocation(latitude: latitude, longitude: longitude)
        let nearest = response.mapItems
            .map { item -> (MKMapItem, CLLocationDistance) in
                let coordinate = item.placemark.coordinate
                let distance = here.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
                return (item, distance)
            }
            .filter { $0.1 <= 500 }
            .min { $0.1 < $1.1 }?
            .0
        guard let nearest else { return nil }
        return place(from: nearest)
    }

    @available(iOS 26.0, *)
    private static func mapKit(_ address: String) async -> LocatedPlace? {
        guard let request = MKGeocodingRequest(addressString: address) else { return nil }
        guard let item = try? await request.mapItems.first else { return nil }
        return place(from: item)
    }

    private static func coreLocation(_ address: String) async -> LocatedPlace? {
        guard let mark = try? await CLGeocoder().geocodeAddressString(address).first,
              let location = mark.location else { return nil }
        let parts = [mark.administrativeArea, mark.locality, mark.subLocality, mark.thoroughfare, mark.subThoroughfare]
        return LocatedPlace(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            name: mark.name ?? "",
            phone: "",
            address: parts.compactMap { $0 }.joined(),
            url: ""
        )
    }

    private static func place(from item: MKMapItem) -> LocatedPlace {
        let mark = item.placemark
        let parts = [mark.administrativeArea, mark.locality, mark.subLocality, mark.thoroughfare, mark.subThoroughfare]
        let url = item.url?.absoluteString ?? ""
        return LocatedPlace(
            latitude: mark.coordinate.latitude,
            longitude: mark.coordinate.longitude,
            name: item.name ?? "",
            phone: item.phoneNumber ?? "",
            address: parts.compactMap { $0 }.joined(),
            url: WorkplaceRead.urlClass(url) == .official ? url : ""
        )
    }
}

enum WorkplaceMaps {
    static func read(_ raw: String) async -> WorkplaceDraft {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) ?? firstURL(trimmed), isMap(url) else {
            var draft = WorkplaceDraft()
            draft.mapsNotice = WorkplaceDraft.mapsUnreadable
            return draft
        }
        let expanded = await expand(url)
        let pin = WorkplaceRead.pin(from: expanded)
        guard let latitude = pin.latitude, let longitude = pin.longitude, !pin.name.isEmpty else {
            var draft = WorkplaceDraft()
            draft.name = pin.name
            if !pin.name.isEmpty {
                draft.nameNote = FieldNote(choices: [pin.name], confidence: .review)
            }
            draft.mapsNotice = WorkplaceDraft.mapsUnreadable
            return draft
        }
        guard let found = await WorkplaceLocator.search(name: pin.name, latitude: latitude, longitude: longitude) else {
            var draft = WorkplaceDraft()
            draft.name = pin.name
            draft.nameNote = FieldNote(choices: [pin.name], confidence: .review)
            draft.mapsNotice = WorkplaceDraft.mapsUnreadable
            return draft
        }
        var draft = WorkplaceDraft()
        draft.name = found.name.isEmpty ? pin.name : found.name
        draft.phone = WorkplaceRead.validPhone(found.phone) ?? ""
        draft.address = WorkplaceRead.validAddress(found.address) ?? found.address
        draft.officialURL = found.url
        draft.nameNote = note(draft.name)
        draft.phoneNote = note(draft.phone)
        draft.addressNote = note(draft.address)
        draft.urlNote = note(draft.officialURL)
        draft.latitude = found.latitude
        draft.longitude = found.longitude
        draft.hasCoordinate = true
        draft.locatedName = found.name
        draft.locateFromAddress = false
        return draft
    }

    private static func note(_ value: String) -> FieldNote {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return FieldNote(confidence: .missing) }
        return FieldNote(choices: [trimmed], confidence: .high, origin: .map)
    }

    private static func isMap(_ url: URL) -> Bool {
        let host = (url.host ?? "").lowercased()
        return host.contains("google.") || host.contains("goo.gl") || host.contains("maps.app")
    }

    private static func firstURL(_ text: String) -> URL? {
        guard let expression = try? NSRegularExpression(pattern: #"https?://[^\s　]+"#) else { return nil }
        let ns = text as NSString
        guard let match = expression.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return URL(string: ns.substring(with: match.range))
    }

    /// Follows redirects for a short link. The body is not read as a page.
    private static func expand(_ url: URL) async -> URL {
        guard WorkplaceRead.isShortMapLink(url) else { return url }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 8
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return response.url ?? url
        } catch {
            return url
        }
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

enum WorkplaceModel {
    static func pick(lines: [ReadLine]) async -> LinePick? {
        guard !lines.isEmpty else { return nil }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return await ModelPick.run(lines)
        }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, *)
@Generable
struct WorkplaceLineIDs {
    @Guide(description: "店名の行ID。渡した番号だけ。最大3つ。無ければ空")
    var nameIDs: [Int]

    @Guide(description: "電話番号の行ID。渡した番号だけ。最大3つ。無ければ空")
    var phoneIDs: [Int]

    @Guide(description: "住所の行ID。渡した番号だけ。最大3つ。無ければ空")
    var addressIDs: [Int]

    @Guide(description: "営業時間の行ID。渡した番号だけ。最大3つ。無ければ空")
    var hoursIDs: [Int]

    @Guide(description: "公式サイトの行ID。地図、食べログ、SNSは入れない。最大3つ。無ければ空")
    var urlIDs: [Int]
}

@available(iOS 26.0, *)
enum ModelPick {
    static func run(_ lines: [ReadLine]) async -> LinePick? {
        guard case .available = SystemLanguageModel.default.availability else { return nil }
        let listed = lines.prefix(80).map { "\($0.id) \($0.text)" }.joined(separator: "\n")
        let session = LanguageModelSession(instructions: """
        勤務先の読み取りです。渡した行IDだけを選んでください。店名や住所の文字列は作らないでください。リストに無い番号は返さないでください。
        """)
        let prompt = """
        次の行から、店名、電話、住所、営業時間、公式サイトに当たる行IDを選んでください。

        \(listed)
        """
        do {
            let response = try await session.respond(to: prompt, generating: WorkplaceLineIDs.self)
            let allowed = Set(lines.map(\.id))
            let content = response.content
            return LinePick(
                nameIDs: content.nameIDs.filter { allowed.contains($0) },
                phoneIDs: content.phoneIDs.filter { allowed.contains($0) },
                addressIDs: content.addressIDs.filter { allowed.contains($0) },
                hoursIDs: content.hoursIDs.filter { allowed.contains($0) },
                urlIDs: content.urlIDs.filter { allowed.contains($0) }
            )
        } catch {
            return nil
        }
    }
}
#endif
