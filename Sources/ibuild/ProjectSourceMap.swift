import Foundation

class ProjectSourceMap: Codable {
    private var plistURL: URL! = nil
    var locations: [String: String] {
        didSet {
            if let data = try? PropertyListEncoder().encode(self) {
                try? data.write(to: plistURL)
            }
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

    private enum CodingKeys: CodingKey {
        case locations
    }

    private init(plistURL: URL) {
        self.plistURL = plistURL
        self.locations = [:]
    }
}