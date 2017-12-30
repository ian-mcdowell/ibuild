import Foundation

enum DependencyError: LocalizedError {
    case invalidURL(String)

    var errorDescription: String? {
        switch self {
            case .invalidURL(let url): return "Invalid URL found while parsing dependency tree: \(url)"
        }
    }
}

struct DependencyDownloader {

    /// Download the dependencies of the given package. These dependencies should all be git repositories with build.plists in them.
    static func downloadDependencies(ofPackage package: Package, intoSourceRoot sourceRoot: URL, projectSourceMap: ProjectSourceMap) throws -> [Package] {
        var packages: [Package] = []
        for dependency in package.dependencies {
            let downloadLocation = try downloadLibrary(dependency, intoSourceRoot: sourceRoot, projectSourceMap: projectSourceMap)

            let downloadedPackage = try Package.inProject(fileURL: downloadLocation)
            packages.append(downloadedPackage)

            packages.append(contentsOf: try downloadDependencies(ofPackage: downloadedPackage, intoSourceRoot: sourceRoot, projectSourceMap: projectSourceMap))
        }
        try downloadLibrary(package.library, intoSourceRoot: sourceRoot, projectSourceMap: projectSourceMap)

        return packages
    }

    @discardableResult
    static func downloadLibrary(_ library: Package.Library, intoSourceRoot sourceRoot: URL, projectSourceMap: ProjectSourceMap) throws -> URL {
        guard let url = URL(string: library.url) else {
            throw DependencyError.invalidURL(library.url)
        }
        let downloadLocation: URL
        if let location = projectSourceMap.locations[library.url] {
            print("Dependency: \(library.url) already downloaded.")
            downloadLocation = URL(fileURLWithPath: location)
            try gitPull(repository: downloadLocation)
        } else {
            let uuid = UUID().uuidString
            downloadLocation = sourceRoot.appendingPathComponent(uuid)
            try gitClone(url: url, destination: downloadLocation)
            try gitCheckout(branch: library.branch, repository: downloadLocation)
            projectSourceMap.locations[library.url] = downloadLocation.path
        }
        return downloadLocation
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