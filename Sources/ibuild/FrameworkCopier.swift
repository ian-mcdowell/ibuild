import Foundation

enum FrameworkCopyError: LocalizedError {
    case packageNotDownloaded(URL)
    case notRunFromXcode
    case outputFilesNotFound(String)

    var errorDescription: String? {
        switch self {
            case .packageNotDownloaded(let url): return "Dependency not downloaded: \(url)"
            case .notRunFromXcode: return "Unable to run copy-frameworks, because required environment variables were missing. Please run as an Xcode build script."
            case .outputFilesNotFound(let name): return "Output files not found: \(name))"
        }
    }
}

struct FrameworkCopier {
    private let package: Package
    private let packageRoot: URL
    private let buildProductsRoot: URL
    init(package: Package, packageRoot: URL, buildProductsRoot: URL) {
        self.package = package; self.packageRoot = packageRoot; self.buildProductsRoot = buildProductsRoot
    }

    func copyFrameworks() throws {
        let frameworks = try FileManager.default.contentsOfDirectory(at: self.buildProductsRoot, includingPropertiesForKeys: nil, options: .skipsSubdirectoryDescendants).filter { $0.pathExtension == "framework" }

        let environment = ProcessInfo.processInfo.environment
        guard 
            let frameworksPath = environment["FRAMEWORKS_FOLDER_PATH"],
            let targetBuildDir = environment["TARGET_BUILD_DIR"]
        else {
            throw FrameworkCopyError.notRunFromXcode
        }

        let frameworksFolder = URL(fileURLWithPath: targetBuildDir).appendingPathComponent(frameworksPath)
        // Make frameworks folder if it doesn't exist
        try Command.tryExec("/bin/mkdir", ["-p", frameworksFolder.path])

        print(" > Copying frameworks to \(frameworksFolder.path)")

        for framework in frameworks {
            try copyFramework(framework, to: frameworksFolder)
        }
    }

    private func copyFramework(_ framework: URL, to frameworksFolder: URL) throws {
        print("\t > Copying framework: \(framework.lastPathComponent)")
        try Command.cp(from: framework, to: frameworksFolder)

        let frameworkURL = frameworksFolder.appendingPathComponent(framework.lastPathComponent)
        for folderName in ["Headers", "PrivateHeaders", "Modules"] {
            try Command.tryExec("/bin/rm", ["-rf", frameworkURL.appendingPathComponent(folderName).path])
        }

        try codesign(frameworkURL)
    }

    private func codesign(_ frameworkURL: URL) throws {
        let environment = ProcessInfo.processInfo.environment
        guard 
            let codesigningAllowed = environment["CODE_SIGNING_ALLOWED"],
            codesigningAllowed == "YES",
            let codesignIdentity = environment["EXPANDED_CODE_SIGN_IDENTITY"],
            !codesignIdentity.isEmpty
        else {
            return
        }

        print("\t > Codesigning framework: \(frameworkURL.lastPathComponent)")

        try Command.tryExec("/usr/bin/xcrun", ["codesign", "--force", "--sign", codesignIdentity, "--preserve-metadata=identifier,entitlements", frameworkURL.path])
    }
}
