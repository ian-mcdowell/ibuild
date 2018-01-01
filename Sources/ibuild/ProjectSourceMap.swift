import Foundation

class ProjectSourceMap: Codable {
    private var plistURL: URL! = nil

    // Maps project names to file URLs
    private var locations: [String: String] {
        didSet {
            self.save()
        }
    }

    static func inRoot(_ root: URL) -> ProjectSourceMap {
        let plistURL = root.appendingPathComponent("dependencies.plist")
        do {
            let data = try Data(contentsOf: plistURL)
            let decoder = PropertyListDecoder()
            let map = try decoder.decode(ProjectSourceMap.self, from: data)
            map.plistURL = plistURL
            return map
        } catch {
            return ProjectSourceMap(plistURL: plistURL)
        }
    }

    public func location(ofProjectAt projectURL: URL) -> URL? {
        if let value = self.locations[projectURL.absoluteString] {
            return URL(fileURLWithPath: value)
        }
        return nil
    }

    public func set(location downloadLocation: URL, ofProjectAt location: URL) {
        self.locations[location.absoluteString] = downloadLocation.path
    }

    private enum CodingKeys: CodingKey {
        case locations
    }

    private init(plistURL: URL) {
        self.plistURL = plistURL
        self.locations = [:]
    }

    private func save() {
        if let data = try? PropertyListEncoder().encode(self) {
            try? data.write(to: plistURL)
        }
    }
}