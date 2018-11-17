import Foundation
import CommonCrypto

enum PackageError: LocalizedError {
    case buildPlistNotFound(url: URL)
    case parsingError(error: Error)
    case invalidURL(url: String)
    case missingItemInKeySequence

    var errorDescription: String? {
        switch self {
            case .buildPlistNotFound(let url): return "A build.plist was not found in the root of this package: \(url.path)"
            case .parsingError(let error): return "Error parsing package property list: \(error)."
            case .invalidURL(let url): return "Invalid URL found while parsing: \(url)"
            case .missingItemInKeySequence: return "Missing required item in key sequence."
        }
    }
}

struct Package: Decodable {

    /// Loaded from a build.plist file and convertible to a custom key sequence (string array)
    ///
    /// Example key sequences:
    ///     <L | github | path | branch>
    ///     <L | git | https://test.com/asdf.git | master>
    ///     <L | local | ../test/hello>
    enum Location: Decodable {
        case github(path: String, branch: String)
        case git(url: URL, branch: String)
        case tar(url: URL)
        case local(path: String)

        private enum CodingKeys: String, CodingKey {
            case type, path, branch, url
        }
        private enum LibraryType: String, Decodable {
            case github, git, tar, local
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
            case .tar:
                let urlStr = try container.decode(String.self, forKey: .url)
                guard let url = URL(string: urlStr) else {
                    throw PackageError.invalidURL(url: urlStr)
                }
                self = .tar(url: url)
            case .local:
                let path = try container.decode(String.self, forKey: .path)
                self = .local(path: path)
            }
        }
        init(from keySequence: [String]) throws {
            guard 
                let typeStr = keySequence[safe: 0],
                let type = LibraryType.init(rawValue: typeStr),
                let pathOrURL = keySequence[safe: 1]
            else {
                throw PackageError.missingItemInKeySequence
            }

            switch type {
            case .github:
                guard let branch = keySequence[safe: 2] else {
                    throw PackageError.missingItemInKeySequence
                }
                self = .github(path: pathOrURL, branch: branch)
            case .git:
                guard let url = URL(string: pathOrURL) else {
                    throw PackageError.invalidURL(url: pathOrURL)
                }
                guard let branch = keySequence[safe: 2] else {
                    throw PackageError.missingItemInKeySequence
                }
                self = .git(url: url, branch: branch)
            case .tar:
                guard let url = URL(string: pathOrURL) else {
                    throw PackageError.invalidURL(url: pathOrURL)
                }
                self = .tar(url: url)
            case .local:
                self = .local(path: pathOrURL)
            }
        }

        func remoteLocation(packageRoot: URL) throws -> URL {
            switch self {
            case .github(let path, _):
                return URL(string: "https://github.com/\(path).git")!
            case .git(let url, _), .tar(let url):
                return url
            case .local(let path):
                let url: URL
                if path.hasPrefix("/") {
                    url = URL(fileURLWithPath: path).standardizedFileURL
                } else {
                    url = packageRoot.appendingPathComponent(path).standardizedFileURL
                }
                return url
            }
        }

        func asKeySequence() -> [String] {
            switch self {
            case .github(let path, let branch):
                return [LibraryType.github.rawValue, path, branch]
            case .git(let url, let branch):
                return [LibraryType.git.rawValue, url.absoluteString, branch]
            case .tar(let url):
                return [LibraryType.tar.rawValue, url.absoluteString]
            case .local(let path):
                return [LibraryType.local.rawValue, path]
            }
        }

        var sha1: String {
            guard let data = self.asKeySequence().joined(separator: "/").data(using: String.Encoding.utf8) else { return "" }

            let hash = data.withUnsafeBytes { (bytes: UnsafePointer<Data>) -> [UInt8] in
                var hash: [UInt8] = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
                CC_SHA1(bytes, CC_LONG(data.count), &hash)
                return hash
            }

            return hash.map { String(format: "%02x", $0) }.joined()
        }
    }

    struct BuildProperties: Decodable {
        // Library the package will build
        let location: Location?

        // Build system to use
        let buildSystem: BuildSystem

        // Package-relative patch files to apply to the library's source code after retrieving.
        let patches: [String]?

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
        let configure: String?
        // Command to make sources
        let make: String?
        // Command to install built libraries
        let install: String?
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
    static func inProject(fileURL: URL) throws -> Package {
        let packageURL = fileURL.appendingPathComponent("build.plist")
        if !FileManager.default.fileExists(atPath: packageURL.path) {
            throw PackageError.buildPlistNotFound(url: fileURL)
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
