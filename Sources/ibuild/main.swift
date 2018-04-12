import Foundation

enum IBuildError: LocalizedError {
    case packageNotFoundInPackageRoot

    var errorDescription: String? {
        switch self {
            case .packageNotFoundInPackageRoot: return "A build.plist was not found in the root of this package."
        }
    }
}

do {
    let environment = ProcessInfo.processInfo.environment
    // Get package root (where the current package to build is)
    let packageRootPath = FileManager.default.currentDirectoryPath
    
    if environment["IBUILD_CURRENT_PACKAGE_ROOT"] == packageRootPath {
        print("ibuild is already building this package. Exiting.")
        exit(0)
    }

    let packageRoot = URL(fileURLWithPath: packageRootPath)
    let filesRoot = packageRoot.appendingPathComponent(".ibuild")
    let sourceRoot = filesRoot.appendingPathComponent("checkout")
    let buildRoot: URL
    if let configBuildDir = environment["CONFIGURATION_BUILD_DIR"] {
        buildRoot = URL(fileURLWithPath: configBuildDir).appendingPathComponent("ibuild")
    } else {
        buildRoot = filesRoot.appendingPathComponent("build")
    }

    // Get the project source map for this package
    let projectSourceMap = ProjectSourceMap.inRoot(filesRoot)

    // Save the root package's location into the map
    projectSourceMap.set(location: packageRoot, ofProjectAt: packageRoot)

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

        // Get its dependencies
        print("\n > Fetching dependencies")
        let dependencies = try DependencyDownloader.downloadDependencies(ofPackage: package, intoSourceRoot: sourceRoot, packageRoot: packageRoot, projectSourceMap: projectSourceMap)

        // Sort dependencies into build order
        let sorted = DependencySorter.buildOrder(forBuilding: dependencies)

        if !sorted.isEmpty {
            print("\n > Building dependencies:")
            for dependency in sorted {
                print("\t\(dependency.package.name)")
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
                print("\n > Fetching library")
                if let location = buildProperties.location {
                    try DependencyDownloader.downloadLibrary(at: location, intoSourceRoot: sourceRoot, packageRoot: packageRoot, projectSourceMap: projectSourceMap)
                }

                print("\n > Building library")
                // Build library
                if let builder = try Builder.forPackage(package, packageRoot: packageRoot, projectSourceMap: projectSourceMap, buildRoot: buildRoot) {
                    try builder.build()
                }
            }
        }
        
        // Generate licenses plist
        var allPackages = sorted
        allPackages += [(package, packageRoot)]
        let location = buildRoot.appendingPathComponent("Licenses.plist")
        
        print("\n > Generating licenses plist for packages. It will be located at: \(location.path)")
        try LicensePlistGenerator.writePlist(forPackages: allPackages, toFile: location, projectSourceMap: projectSourceMap)

        print("\n > ibuild completed successfully.")
        print("Built packages: \(allPackages.count)")
    case "clean":
        if FileManager.default.fileExists(atPath: buildRoot.path) {
            try FileManager.default.removeItem(at: buildRoot)
        }
        print("\n > Successfully cleaned project.")
    case "copy-frameworks":

        // Load the build.plist of the current directory
        guard let package = try Package.inProject(fileURL: packageRoot) else {
            throw IBuildError.packageNotFoundInPackageRoot
        }

        try FrameworkCopier(package: package, packageRoot: packageRoot, buildRoot: buildRoot, projectSourceMap: projectSourceMap).copyFrameworks()
    default:
        print("Invalid action: \(action). Options are: \"build\", \"archive\", \"clean\", \"copy-frameworks\".")
    }

} catch {
    print(error.localizedDescription)
    exit(1)
}
