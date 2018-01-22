import Foundation

enum PackageError: LocalizedError {
    case parsingError(error: Error)
    case invalidURL(url: String)

    var errorDescription: String? {
        switch self {
            case .parsingError(let error): return "Error parsing package property list: \(error.localizedDescription)."
            case .invalidURL(let url): return "Invalid URL found while parsing: \(url)"
        }
    }
}

struct Package: Decodable {

    enum Location: Decodable {
        case github(path: String, branch: String)
        case git(url: URL, branch: String)
        case local(path: String)

        private enum CodingKeys: String, CodingKey {
            case type, path, branch, url
        }
        private enum LibraryType: String, Decodable {
            case github, git, local
        }
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(LibraryType.self, forKey: .type)

            switch type {
            case .github:
                let path = try container.decode(String.self, forKey: .path)
                let branch = try container.decode(String.self, forKey: .branch)
                self = .github(path: path, branch: branch)
            case .git:
                let urlStr = try container.decode(String.self, forKey: .url)
                guard let url = URL(string: urlStr) else {
                    throw PackageError.invalidURL(url: urlStr)
                }
                let branch = try container.decode(String.self, forKey: .branch)
                self = .git(url: url, branch: branch)
            case .local:
                let path = try container.decode(String.self, forKey: .path)
                self = .local(path: path)
            }
        }

        func remoteLocation() throws -> URL {
            switch self {
            case .github(let path, _):
                return URL(string: "https://github.com/\(path).git")!
            case .git(let url, _):
                return url
            case .local(let path):
                let url: URL
                if path.hasPrefix("/") {
                    url = URL(fileURLWithPath: path)
                } else {
                    guard let packageRoot = ProcessInfo.processInfo.environment["PACKAGE_ROOT"] else {
                        throw IBuildError.packageRootNotFound
                    }
                    url = URL(fileURLWithPath: "\(packageRoot)/\(path)")
                }
                return url
            }
        }
    }

    struct BuildProperties: Decodable {
        // Library the package will build
        let location: Location?

        // Build system to use
        let buildSystem: BuildSystem

        // Arguments to pass to the configure script
        let buildArgs: [String]?

        // Additional arguments to pass to the configure script, dependent on architecture
        let buildArchSpecificArgs: [String: [String: [String]]]?

        // Command to pass to make to install software
        let installCommand: String?

        // Paths of the libraries that are built
        let outputs: [String]?

        // Paths of source files in this package to also copy to final output directory.
        let auxiliaryFiles: [String: String]?

        // If the build system is custom, these properties will determine which commands are run.
        let customProperties: CustomBuildSystemProperties?

        enum BuildSystem: String, Decodable {
            case cmake
            case make
            case xcode
            case custom
        }
    }

    struct CustomBuildSystemProperties: Decodable {
        // Command to configure sources
        let configure: String
        // Command to make sources
        let make: String
        // Command to install built libraries
        let install: String
        // Additional environment variables to pass to commands
        let env: [String: String]?
    }

    // Name of the package
    let name: String

    // Properties of thing to build
    let build: BuildProperties?

    // Other packages that must be built first
    let dependencies: [Location]?

    /// Decode a Package from the property list at the given local URL
    static func inProject(fileURL: URL) throws -> Package? {
        let packageURL = fileURL.appendingPathComponent("build.plist")
        if !FileManager.default.fileExists(atPath: packageURL.path) {
            return nil
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