import Foundation
import llbuildSwift

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
    let buildProductsRoot = buildRoot.appendingPathComponent("Products")
    let buildIntermediatesRoot = buildRoot.appendingPathComponent("Intermediates")

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

        // Create .ibuild folder
        try FileManager.default.createDirectory(at: filesRoot, withIntermediateDirectories: true, attributes: nil)

        let buildSystem = BuildSystem(
            packageRoot: packageRoot,
            sourceRoot: sourceRoot, 
            buildProductsRoot: buildProductsRoot,
            buildIntermediatesRoot: buildIntermediatesRoot
        )
        let engine = BuildEngine(delegate: buildSystem)
        try engine.attachDB(path: filesRoot.appendingPathComponent("build.db").path)

        // Build package at our package root, as well as dependencies
        let packageKey = buildSystem.keyForPackage(Package.Location.local(path: packageRoot.path))
        _ = engine.build(key: packageKey)

        print("\n > Successfully built project.")

        engine.close()
        
    case "clean":
        if FileManager.default.fileExists(atPath: buildRoot.path) {
            try FileManager.default.removeItem(at: buildRoot)
        }
        print("\n > Successfully cleaned project.")
    case "copy-frameworks":

        // Load the build.plist of the current directory
        let package = try Package.inProject(fileURL: packageRoot)

        try FrameworkCopier(package: package, packageRoot: packageRoot, buildProductsRoot: buildProductsRoot).copyFrameworks()
    default:
        print("Invalid action: \(action). Options are: \"build\", \"archive\", \"clean\", \"copy-frameworks\".")
    }

} catch {
    print(error.localizedDescription)
    exit(1)
}
