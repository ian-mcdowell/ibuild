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

    let projectSourceMap = ProjectSourceMap.inRoot(filesRoot)

    // Load the package in that root
    let package = try Package.inProject(fileURL: packageRoot)

    // Get its dependencies
    let dependencies = try DependencyDownloader.downloadDependencies(ofPackage: package, intoSourceRoot: sourceRoot, projectSourceMap: projectSourceMap)

    // Sort dependencies into build order
    let sorted = DependencySorter.buildOrder(forBuilding: dependencies)

    print("Build dependencies:")
    for dependency in sorted {
        print("\(dependency.name) - \(dependency.url)")
    }
    for dependency in sorted {
        let packageRoot = URL(fileURLWithPath: projectSourceMap.locations[dependency.url]!)
        let sourceRoot = URL(fileURLWithPath: projectSourceMap.locations[dependency.library.url]!)

        let builder = try Builder.forPackage(dependency, packageRoot: packageRoot, sourceRoot: sourceRoot, buildRoot: buildRoot)
        try builder.build()
    }
} catch {
    print(error.localizedDescription)
}