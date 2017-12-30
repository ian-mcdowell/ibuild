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
    let environment = ProcessInfo.processInfo.environment
    // Get package root (where the current package to build is)
    guard let packageRootEnv = environment["PACKAGE_ROOT"] else {
        throw IBuildError.packageRootNotFound
    }
    let packageRoot = URL(fileURLWithPath: packageRootEnv)
    let filesRoot = packageRoot.appendingPathComponent(".ibuild")
    let sourceRoot = filesRoot.appendingPathComponent("checkout")
    let buildRoot = filesRoot.appendingPathComponent("build")

    // Parse cmd line
    let argc = CommandLine.arguments.count
    let action: String
    if argc > 1 {
        action = CommandLine.arguments[1]
    } else {
        action = "build"
    }

    switch action {
    case "build": 

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
                if let builder = try Builder.forPackage(dependency, projectSourceMap: projectSourceMap, buildRoot: buildRoot) {
                    try builder.build()
                }
            }
        }

        // Download library
        if let library = package.library {
            try DependencyDownloader.downloadLibrary(library, intoSourceRoot: sourceRoot, projectSourceMap: projectSourceMap)
        }

        // Build library
        if let builder = try Builder.forPackage(package, projectSourceMap: projectSourceMap, buildRoot: buildRoot) {
            try builder.build()

            if let modulemap = package.modulemap {
                try Command.cp(from: packageRoot.appendingPathComponent(modulemap), to: buildRoot.appendingPathComponent("include"))
            }
        }

    case "clean":
        try FileManager.default.removeItem(at: buildRoot)
        print("Successfully cleaned project.")
    default:
        print("Invalid action: \(action). Options are: \"build\", \"clean\".")
    }

} catch {
    print(error.localizedDescription)
}