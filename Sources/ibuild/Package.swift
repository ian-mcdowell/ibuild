import Foundation

enum PackageError: LocalizedError {
    case parsingError(error: Error)
    case notFound(url: URL)

    var errorDescription: String? {
        switch self {
            case .parsingError(let error): return "Error parsing package property list: \(error.localizedDescription)."
            case .notFound(let url): return "Package was not found at: \(url.path)"
        }
    }
}

struct Package: Decodable {

    struct Library: Decodable {
        let url: String
        let branch: String
    }

    enum BuildSystem: String, Decodable {
        case cmake
        case make
        case xcode
    }

    // Name of the package
    let name: String

    // Git URL of the package
    let url: String

    // Library the package will build
    let library: Library?

    // Other packages that must be built first
    let dependencies: [Library]

    // Names of the static libraries generated
    let libraryOutputs: [String]?

    // Build system to use
    let buildSystem: BuildSystem
    
    // Arguments to pass to the configure script
    let buildArgs: [String]?

    // Additional arguments to pass to the configure script, dependent on architecture
    let buildArchSpecificArgs: [String: [String: [String]]]?

    // Command to pass to make to install software
    let installCommand: String?

    /// Decode a Package from the property list at the given local URL
    static func inProject(fileURL: URL) throws -> Package {
        let packageURL = fileURL.appendingPathComponent("build.plist")
        if !FileManager.default.fileExists(atPath: packageURL.path) {
            throw PackageError.notFound(url: packageURL)
        }
        let data = try Data(contentsOf: packageURL)
        let decoder = PropertyListDecoder()
        do {
            return try decoder.decode(Package.self, from: data)
        } catch {
            throw PackageError.parsingError(error: error)
        }
    }

}