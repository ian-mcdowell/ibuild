import Foundation

enum IBuildError: LocalizedError {
    case packageRootNotFound

    var errorDescription: String? {
        switch self {
            case .packageRootNotFound: return "Package root not found."
        }
    }
}

do {
    // Get package root (where the current package to build is)
    guard let packageRootEnv = ProcessInfo.processInfo.environment["PACKAGE_ROOT"] else {
        throw IBuildError.packageRootNotFound
    }
    let packageRoot = URL(fileURLWithPath: packageRootEnv)
    let filesRoot = packageRoot.appendingPathComponent(".ibuild")
    let sourceRoot = filesRoot.appendingPathComponent("checkout")
    let buildRoot = filesRoot.appendingPathComponent("build")

    // Load the package in that root
    let package = try Package.inProject(fileURL: packageRoot)

    // Get the project source map for this package
    let projectSourceMap = ProjectSourceMap.inRoot(filesRoot)

    // Save the root package into the map
    projectSourceMap.locations[package.url] = packageRoot.path

    // Get its dependencies
    let dependencies = try DependencyDownloader.downloadDependencies(ofPackage: package, intoSourceRoot: sourceRoot, projectSourceMap: projectSourceMap)

    // Sort dependencies into build order
    let sorted = DependencySorter.buildOrder(forBuilding: dependencies)

    if !sorted.isEmpty {
        print("Building dependencies:")
        for dependency in sorted {
            print("\(dependency.name) - \(dependency.url)")
        }
        for dependency in sorted {
            let builder = try Builder.forPackage(dependency, projectSourceMap: projectSourceMap, buildRoot: buildRoot)
            try builder.build()
        }
    }

    // Download library
    try DependencyDownloader.downloadLibrary(package.library, intoSourceRoot: sourceRoot, projectSourceMap: projectSourceMap)

    // Build library
    let builder = try Builder.forPackage(package, projectSourceMap: projectSourceMap, buildRoot: buildRoot)
    try builder.build()
} catch {
    print(error.localizedDescription)
}