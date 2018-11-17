import llbuildSwift
import Foundation

/// Downloads a given location, returning the path
class DownloadPackageLocationRule: LocationRuleProtocol {
    let location: Package.Location
    let buildSystem: BuildSystem

    required init(location: Package.Location, buildSystem: BuildSystem) {
        self.location = location
        self.buildSystem = buildSystem
    }

    func isResultValid(_ priorValue: Value) -> Bool {
        return FileManager.default.fileExists(atPath: priorValue.toString())
    }

    func createTask() -> Task {
        return DownloadPackageLocationTask(rule: self)
    }

    class DownloadPackageLocationTask: Task {
        let rule: DownloadPackageLocationRule

        init(rule: DownloadPackageLocationRule) {
            self.rule = rule
        }

        func start(_ engine: TaskBuildEngine) {

        }

        func provideValue(_ engine: TaskBuildEngine, inputID: Int, value: Value) {

        }

        func inputsAvailable(_ engine: TaskBuildEngine) {
            let rule = self.rule

            // Don't try to download the current package
            switch rule.location {
            case .local(let path):
                if path == rule.buildSystem.packageRoot.path {
                    return engine.taskIsComplete(Value(path), forceChange: false)
                }
            default:
                break
            }

            DispatchQueue.global().async {
                do {
                    let downloadLocation = try DownloadPackageLocationTask.downloadLibrary(
                        at: rule.location,
                        intoSourceRoot: rule.buildSystem.sourceRoot,
                        packageRoot: rule.buildSystem.packageRoot
                    )

                    engine.taskIsComplete(Value(downloadLocation.path), forceChange: false)
                } catch {
                    fatalError(error.localizedDescription)
                }
            }
        }

        @discardableResult
        static func downloadLibrary(at location: Package.Location, intoSourceRoot sourceRoot: URL, packageRoot: URL) throws -> URL {

            let remoteLocation = try location.remoteLocation(packageRoot: packageRoot)
            let downloadLocation = sourceRoot.appendingPathComponent(location.sha1).standardizedFileURL

            print("\t > Retrieving package from: \(remoteLocation.absoluteString)")

            switch location {
            case .github(_, let branch), .git(_, let branch):
                try self.downloadGitPackage(at: remoteLocation, branch: branch, into: downloadLocation)
            case .tar(_):
                try self.downloadAndExtractTar(at: remoteLocation, to: downloadLocation)
            case .local(_):
                // Copy package recursively from local url to the download location
                if remoteLocation != downloadLocation {
                    try self.copyContentsOfDirectory(from: remoteLocation, to: downloadLocation)
                }
            }

            return downloadLocation
        }

        private static func downloadGitPackage(at projectURL: URL, branch: String, into destinationURL: URL) throws {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try gitReset(repository: destinationURL)
                try gitCheckout(branch: branch, repository: destinationURL)
                try gitPull(branch: branch, repository: destinationURL)
            } else {
                try gitClone(url: projectURL, destination: destinationURL)
                try gitCheckout(branch: branch, repository: destinationURL)
            }
        }

        private static func gitClone(url: URL, destination: URL) throws {
            print("\t\t > Cloning with git: \(url.absoluteString)")
            try Command.tryExec("/usr/bin/git", ["clone", "--recursive", url.absoluteString, destination.path])
        }

        private static func gitCheckout(branch: String, repository: URL) throws {
            print("\t\t > Checking out with git: \(repository.absoluteString)")
            try Command.tryExec("/usr/bin/git", currentDirectory: repository.path, ["checkout", branch])
        }

        private static func gitPull(branch: String, repository: URL) throws {
            try Command.tryExec("/usr/bin/git", currentDirectory: repository.path, ["pull", "origin", branch])
        }

        private static func gitReset(repository: URL) throws {
            try Command.tryExec("/usr/bin/git", currentDirectory: repository.path, ["reset", "--hard"])
        }

        private static func copyContentsOfDirectory(from: URL, to: URL) throws {
            try Command.tryExec("/bin/rm", ["-rf", to.path])
            try Command.tryExec("/bin/mkdir", ["-p", to.deletingLastPathComponent().path])
            try Command.tryExec("/bin/cp", ["-R", from.path, to.path])
        }

        private static func downloadAndExtractTar(at: URL, to: URL) throws {
            print("\t\t > Downloading tar: \(at.absoluteString)")
            try Command.tryExec("/bin/rm", ["-rf", to.path])
            try Command.tryExec("/bin/mkdir", ["-p", to.path])
            let tmpFileName = "/tmp/ibuild-download.tar.gz"
            try Command.tryExec("/usr/bin/curl", ["-SL", at.absoluteString, "-o", tmpFileName])
            try Command.tryExec("/usr/bin/tar", ["-xz", "-f", tmpFileName, "-C", to.path, "--strip-components", "1"])
            try Command.tryExec("/bin/rm", ["-rf", tmpFileName])
        }
    }
}
