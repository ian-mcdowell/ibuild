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

    /// Download the dependencies of the given package. These dependencies should all be git repositories with build.plists in them.
    static func downloadDependencies(ofPackage package: Package, intoSourceRoot sourceRoot: URL, projectSourceMap: ProjectSourceMap) throws -> [(package: Package, location: URL)] {
        var packages: [(package: Package, location: URL)] = []
        for dependency in package.dependencies ?? [] {
            let result = try downloadLibrary(at: dependency, intoSourceRoot: sourceRoot, projectSourceMap: projectSourceMap)
            guard let downloadedPackage = result.package else {
                throw DependencyError.packageNotFound(dependency)
            }
            packages.append((downloadedPackage, result.location))
            packages.append(contentsOf: try downloadDependencies(ofPackage: downloadedPackage, intoSourceRoot: sourceRoot, projectSourceMap: projectSourceMap))
        }
        if let location = package.build?.location {
            try downloadLibrary(at: location, intoSourceRoot: sourceRoot, projectSourceMap: projectSourceMap)
        }

        return packages
    }

    @discardableResult
    static func downloadLibrary(at location: Package.Location, intoSourceRoot sourceRoot: URL, projectSourceMap: ProjectSourceMap) throws -> (package: Package?, location: URL) {

        let package: Package?
        let remoteLocation = try location.remoteLocation()
        let downloadLocation: URL

        switch location {
        case .github(_, let branch), .git(_, let branch):
            let result = try self.downloadGitPackage(at: remoteLocation, branch: branch, intoSourceRoot: sourceRoot, projectSourceMap: projectSourceMap)
            package = result.package
            downloadLocation = result.location
        case .local(_):
            package = try Package.inProject(fileURL: remoteLocation)
            downloadLocation = remoteLocation
        }

        // Save where we downloaded the library
        projectSourceMap.set(location: downloadLocation, ofProjectAt: remoteLocation)

        return (package, downloadLocation)
    }

    private static func downloadGitPackage(at projectURL: URL, branch: String, intoSourceRoot sourceRoot: URL, projectSourceMap: ProjectSourceMap) throws -> (package: Package?, location: URL) {
        let downloadLocation: URL
        if let onDiskLocation = projectSourceMap.location(ofProjectAt: projectURL) {
            downloadLocation = onDiskLocation
            print("Github Dependency: \(projectURL.absoluteString) already downloaded.")
            try gitPull(repository: downloadLocation)
        } else {
            let uuid = UUID().uuidString
            downloadLocation = sourceRoot.appendingPathComponent(uuid)
            try gitClone(url: projectURL, destination: downloadLocation)
        }
        try gitCheckout(branch: branch, repository: downloadLocation)

        let package = try Package.inProject(fileURL: downloadLocation)
        return (package, downloadLocation)
    }

    private static func gitClone(url: URL, destination: URL) throws {
        print("Cloning project: \(url.absoluteString)")
        try Command.tryExec("/usr/bin/git", ["clone", "--recursive", url.absoluteString, destination.path])
    }

    private static func gitPull(repository: URL) throws {
        try Command.tryExec("/usr/bin/git", currentDirectory: repository.path, ["pull"])
    }

    private static func gitCheckout(branch: String, repository: URL) throws {
        try Command.tryExec("/usr/bin/git", currentDirectory: repository.path, ["checkout", branch])
    }
}