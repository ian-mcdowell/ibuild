import Foundation

enum DependencyError: LocalizedError {
    case invalidURL(String)
    case packageNotFound(Package.Location)

    var errorDescription: String? {
        switch self {
            case .invalidURL(let url): return "Invalid URL found while parsing dependency tree: \(url)"
            case .packageNotFound(let location): return "build.plist not found at location: \(location)"
        }
    }
}

struct DependencyDownloader {

    /// Download the dependencies of the given package. These dependencies should all be git repositories / directories with build.plists in them.
    static func downloadDependencies(ofPackage package: Package, intoSourceRoot sourceRoot: URL, packageRoot: URL, projectSourceMap: ProjectSourceMap) throws -> [(package: Package, location: URL)] {
        var packages: [(package: Package, location: URL)] = []
        for dependency in package.dependencies ?? [] {
            let result = try downloadLibrary(at: dependency, intoSourceRoot: sourceRoot, packageRoot: packageRoot, projectSourceMap: projectSourceMap)
            guard let downloadedPackage = result.package else {
                throw DependencyError.packageNotFound(dependency)
            }
            packages.append((downloadedPackage, result.location))
            packages.append(contentsOf: try downloadDependencies(ofPackage: downloadedPackage, intoSourceRoot: sourceRoot, packageRoot: result.location, projectSourceMap: projectSourceMap))
        }
        if let location = package.build?.location {
            let result = try downloadLibrary(at: location, intoSourceRoot: sourceRoot, packageRoot: packageRoot, projectSourceMap: projectSourceMap)

            // Apply patches, if there are any
            if let patches = package.build?.patches {
                try self.applyPatches(patches, in: packageRoot, to: result.location)
            }
        }

        return packages
    }

    @discardableResult
    static func downloadLibrary(at location: Package.Location, intoSourceRoot sourceRoot: URL, packageRoot: URL, projectSourceMap: ProjectSourceMap) throws -> (package: Package?, location: URL) {

        let package: Package?
        let remoteLocation = try location.remoteLocation(packageRoot: packageRoot)
        let (downloadLocation, cached) = self.location(forProjectAt: remoteLocation, sourceRoot: sourceRoot, projectSourceMap: projectSourceMap)

        print("\t > Retrieving package from: \(remoteLocation.absoluteString) \(cached ? "Cached" : "Not cached")")

        switch location {
        case .github(_, let branch), .git(_, let branch):
            package = try self.downloadGitPackage(at: remoteLocation, branch: branch, into: downloadLocation, cached: cached, projectSourceMap: projectSourceMap)
        case .tar(_):
            try self.downloadAndExtractTar(at: remoteLocation, to: downloadLocation)
            package = try Package.inProject(fileURL: downloadLocation)
        case .local(_):
            // Copy package recursively from local url to the download location
            try self.copyContentsOfDirectory(from: remoteLocation, to: downloadLocation)
            package = try Package.inProject(fileURL: downloadLocation)
        }

        // Save where we downloaded the library
        projectSourceMap.set(location: downloadLocation, ofProjectAt: remoteLocation)

        return (package, downloadLocation)
    }

    private static func downloadGitPackage(at projectURL: URL, branch: String, into destinationURL: URL, cached: Bool, projectSourceMap: ProjectSourceMap) throws -> Package? {
        if cached {
            try gitReset(repository: destinationURL)
            try gitCheckout(branch: branch, repository: destinationURL)
            try gitPull(branch: branch, repository: destinationURL)
        } else {
            try gitClone(url: projectURL, destination: destinationURL)
            try gitCheckout(branch: branch, repository: destinationURL)
        }

        return try Package.inProject(fileURL: destinationURL)
    }

    private static func location(forProjectAt projectURL: URL, sourceRoot: URL, projectSourceMap: ProjectSourceMap) -> (url: URL, cached: Bool) {
        if let onDiskLocation = projectSourceMap.location(ofProjectAt: projectURL) {
            return (onDiskLocation, true)
        }
        return (sourceRoot.appendingPathComponent(UUID().uuidString).standardizedFileURL, false)
    }

    private static func gitClone(url: URL, destination: URL) throws {
        print("\t > Cloning project: \(url.absoluteString)")
        try Command.tryExec("/usr/bin/git", ["clone", "--recursive", url.absoluteString, destination.path])
    }

    private static func gitPull(branch: String, repository: URL) throws {
        try Command.tryExec("/usr/bin/git", currentDirectory: repository.path, ["pull", "origin", branch])
    }

    private static func gitReset(repository: URL) throws {
        try Command.tryExec("/usr/bin/git", currentDirectory: repository.path, ["reset", "--hard"])
    }

    private static func gitCheckout(branch: String, repository: URL) throws {
        try Command.tryExec("/usr/bin/git", currentDirectory: repository.path, ["checkout", branch])
    }

    private static func copyContentsOfDirectory(from: URL, to: URL) throws {
        try Command.tryExec("/bin/rm", ["-rf", to.path])
        try Command.tryExec("/bin/mkdir", ["-p", to.deletingLastPathComponent().path])
        try Command.tryExec("/bin/cp", ["-R", from.path, to.path])
    }

    private static func downloadAndExtractTar(at: URL, to: URL) throws {
        print("\t > Downloading tar: \(at.absoluteString)")
        try Command.tryExec("/bin/rm", ["-rf", to.path])
        try Command.tryExec("/bin/mkdir", ["-p", to.path])
        let tmpFileName = "/tmp/ibuild-download.tar.gz"
        try Command.tryExec("/usr/bin/curl", ["-SL", at.absoluteString, "-o", tmpFileName])
        try Command.tryExec("/usr/bin/tar", ["-xz", "-f", tmpFileName, "-C", to.path, "--strip-components", "1"])
        try Command.tryExec("/bin/rm", ["-rf", tmpFileName])
    }

    private static func applyPatches(_ patches: [String], in patchesURL: URL, to: URL) throws {
        print("\t > Applying patches: \(patches)")
        for patch in patches {
            try Command.tryExec("/usr/bin/patch", currentDirectory: to.path, ["-p", "1", "-i", patchesURL.appendingPathComponent(patch).path])
        }
    }
}