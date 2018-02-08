import Foundation

// MARK: String Extensions

fileprivate extension String {
    func endsWith(str: String) -> Bool {
        if let range = self.range(of: str, options:.backwards) {
            return range.upperBound == self.endIndex
        }
        return false
    }
}

struct LicensePlistGenerator {
    
    private typealias LicensePlistType = [String: String]
    
    static func writePlist(forPackages packages: [(package: Package, location: URL)], toFile: URL, projectSourceMap: ProjectSourceMap) throws {
        
        var licenses: LicensePlistType
        do {
            let data = try Data(contentsOf: toFile)
            let decoder = PropertyListDecoder()
            licenses = try decoder.decode(LicensePlistType.self, from: data)
        } catch {
            licenses = [:]
        }
        
        for (package, locationOnDisk) in packages {
            
            guard
                let licensePath = locateLicenseInFolder(folder: locationOnDisk),
                let license = try? String(contentsOf: licensePath, encoding: .utf8)
            else {
                print("\t > Unable to find license for package: \(package.name) in \(locationOnDisk).")
                continue
            }
            
            print("\t > Adding \(package.name)'s license to licenses plist")
            
            licenses[package.name] = license
        }

        // Generate plist from result array
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let plist = try encoder.encode(licenses)
        
        // Write plist to disk
        try plist.write(to: toFile, options: .atomic)
    }
    
    // MARK: Internal functions
    
    private static func locateLicenseInFolder(folder: URL) -> URL? {
        let filemanager = FileManager.default
        
        if let subpaths = try? filemanager.contentsOfDirectory(atPath: folder.path),
            let license = subpaths.first(where: { $0 == "LICENSE" || $0 == "LICENSE.txt" }) {
            return folder.appendingPathComponent(license)
        }
        return nil
    }

}
