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
    
    static func writePlist(forPackages packages: [Package], toFile: URL, projectSourceMap: ProjectSourceMap) throws {
        
        var licenses: LicensePlistType
        do {
            let data = try Data(contentsOf: toFile)
            let decoder = PropertyListDecoder()
            licenses = try decoder.decode(LicensePlistType.self, from: data)
        } catch {
            licenses = [:]
        }
        
        for package in packages {
            
            guard
                let location = package.build?.location,
                let remoteLocation = try? location.remoteLocation(),
                let locationOnDisk = projectSourceMap.location(ofProjectAt: remoteLocation)
            else {
                print("Unable to find source location of package: \(package.name).")
                continue
            }
            
            guard
                let licensePath = locateLicenseInFolder(folder: locationOnDisk),
                let license = try? String(contentsOf: licensePath, encoding: .utf8)
            else {
                print("Unable to find license for package: \(package.name) in \(locationOnDisk).")
                continue
            }
            
            print("Adding \(package.name)'s license to licenses plist")
            
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
        
        if let subpaths = try? filemanager.subpathsOfDirectory(atPath: folder.path),
            let license = subpaths.first(where: { $0.endsWith(str: "LICENSE") || $0.endsWith(str: "LICENSE.txt") }) {
            return folder.appendingPathComponent(license)
        }
        return nil
    }

}
