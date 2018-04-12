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
    private let buildRoot: URL
    private let projectSourceMap: ProjectSourceMap
    init(package: Package, packageRoot: URL, buildRoot: URL, projectSourceMap: ProjectSourceMap) {
        self.package = package; self.packageRoot = packageRoot; self.buildRoot = buildRoot; self.projectSourceMap = projectSourceMap
    }

    func copyFrameworks() throws {
        let frameworks = try self.frameworks()

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
            try copyFramework(self.buildRoot.appendingPathComponent(framework), to: frameworksFolder)
        }
    }

    private func frameworks() throws -> [String] {
        let dependencies = try self.dependencies(ofPackage: package, packageRoot: self.packageRoot)
        var frameworkNames = dependencies.flatMap { dependency -> [String] in 
            guard let outputs = dependency.build?.outputs else { return [] }
            return outputs.filter { $0.hasSuffix(".framework") }
        }
        // Remove duplicates
        frameworkNames = Array(Set(frameworkNames))

        return frameworkNames
    }

    private func dependencies(ofPackage package: Package, packageRoot: URL) throws -> [Package] {
        var packages = [package]
        guard let dependencies = package.dependencies else { return packages }
        for location in dependencies {
            let projectURL = try location.remoteLocation(packageRoot: packageRoot)
            guard 
                let location = projectSourceMap.location(ofProjectAt: projectURL),
                let package = try Package.inProject(fileURL: location)
            else {
                throw FrameworkCopyError.packageNotDownloaded(projectURL)
            }
            packages.append(contentsOf: try self.dependencies(ofPackage: package, packageRoot: location))
        }
        return packages
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