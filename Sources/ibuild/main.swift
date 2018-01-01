import Foundation

enum IBuildError: LocalizedError {
    case packageRootNotFound
    case packageNotFoundInPackageRoot

    var errorDescription: String? {
        switch self {
            case .packageRootNotFound: return "Package root not found."
            case .packageNotFoundInPackageRoot: return "A build.plist was not found in the root of this package."
        }
    }
}

do {
    let environment = ProcessInfo.processInfo.environment
    // Get package root (where the current package to build is)
    guard let packageRootEnv = environment["PACKAGE_ROOT"] else {
        throw IBuildError.packageRootNotFound
    }
    
    if environment["IBUILD_CURRENT_PACKAGE_ROOT"] == packageRootEnv {
        print("ibuild is already building this package. Exiting.")
        exit(0)
    }

    let packageRoot = URL(fileURLWithPath: packageRootEnv)
    let filesRoot = packageRoot.appendingPathComponent(".ibuild")
    let sourceRoot = filesRoot.appendingPathComponent("checkout")
    let buildRoot: URL
    if let configBuildDir = environment["CONFIGURATION_BUILD_DIR"] {
        buildRoot = URL(fileURLWithPath: configBuildDir).appendingPathComponent("ibuild")
    } else {
        buildRoot = filesRoot.appendingPathComponent("build")
    }

    // Parse cmd line
    let argc = CommandLine.arguments.count
    let action: String
    if argc > 1 {
        action = CommandLine.arguments[1]
    } else {
        action = "build"
    }

    switch action {
    case "build", "archive", "install", "test": 

        // Load the build.plist of the current directory
        guard let package = try Package.inProject(fileURL: packageRoot) else {
            throw IBuildError.packageNotFoundInPackageRoot
        }

        // Get the project source map for this package
        let projectSourceMap = ProjectSourceMap.inRoot(filesRoot)

        // Save the root package's location into the map
        projectSourceMap.set(location: packageRoot, ofProjectAt: packageRoot)

        // Get its dependencies
        let dependencies = try DependencyDownloader.downloadDependencies(ofPackage: package, intoSourceRoot: sourceRoot, projectSourceMap: projectSourceMap)

        // Sort dependencies into build order
        let sorted = DependencySorter.buildOrder(forBuilding: dependencies)

        if !sorted.isEmpty {
            print("Building dependencies:")
            for dependency in sorted {
                print(dependency.package.name)
            }
            for dependency in sorted {
                if let builder = try Builder.forPackage(dependency.package, packageRoot: dependency.location, projectSourceMap: projectSourceMap, buildRoot: buildRoot) {
                    try builder.build()
                }
            }
        }

        if environment["IBUILD_DEPENDENCIES_ONLY"] != "YES" {
            // Download library
            if let buildProperties = package.build {
                if let location = buildProperties.location {
                    try DependencyDownloader.downloadLibrary(at: location, intoSourceRoot: sourceRoot, projectSourceMap: projectSourceMap)
                }

                // Build library
                if let builder = try Builder.forPackage(package, packageRoot: packageRoot, projectSourceMap: projectSourceMap, buildRoot: buildRoot) {
                    try builder.build()
                }
            }
        }

    case "clean":
        try FileManager.default.removeItem(at: buildRoot)
        print("Successfully cleaned project.")
    default:
        print("Invalid action: \(action). Options are: \"build\", \"archive\", \"clean\".")
    }

} catch {
    print(error.localizedDescription)
    exit(1)
}
