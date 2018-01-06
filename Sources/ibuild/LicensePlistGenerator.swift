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
    
    static func writePlist(forPackages packages: [Package], toFile: URL, projectSourceMap: ProjectSourceMap) throws {
        var licenses = [[String: String]]()
        
        for package in packages {
            
            guard
                let location = package.build?.location,
                let locationOnDisk = projectSourceMap.location(ofProjectAt: try location.remoteLocation()),
                let licensePath = locateLicenseInFolder(folder: locationOnDisk),
                let licence = try? String(contentsOf: licensePath, encoding: .utf8)
            else {
                continue
            }
            
            licenses.append(["title": package.name, "text": licence])
        }

        // Generate plist from result array
        let plist = try PropertyListSerialization.data(fromPropertyList: licenses, format: .xml, options: 0)
        
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
