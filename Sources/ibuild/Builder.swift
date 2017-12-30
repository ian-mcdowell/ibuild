import Foundation

class Builder {
    static func forPackage(_ package: Package, projectSourceMap: ProjectSourceMap, buildRoot: URL) throws -> Builder {
        let packageRoot = URL(fileURLWithPath: projectSourceMap.locations[package.url]!)
        let sourceRoot = URL(fileURLWithPath: projectSourceMap.locations[package.library.url]!)
        switch package.buildSystem {
            case .cmake: return try CMakeBuilder(package: package, packageRoot: packageRoot, sourceRoot: sourceRoot, buildRoot: buildRoot)
            case .make: return try MakeBuilder(package: package, packageRoot: packageRoot, sourceRoot: sourceRoot, buildRoot: buildRoot)
        }
    }

    let package: Package
    let env: [String: String]

    let architectures: [String]
    /// Root of the package that's building the library
    let packageRoot: URL
    /// Root of the library to be built
    let sourceRoot: URL
    let buildRoot: URL
    let buildProducts: URL
    let sysroot: URL
    let deploymentTarget: String

    init(package: Package, packageRoot: URL, sourceRoot: URL, buildRoot: URL) throws {
        self.package = package
        self.packageRoot = packageRoot
        self.sourceRoot = sourceRoot
        self.buildRoot = buildRoot

        let environment = ProcessInfo.processInfo.environment
        self.buildProducts = buildRoot.appendingPathComponent("products").appendingPathComponent(sourceRoot.lastPathComponent)

        if let archs = environment["ARCHS"] {
            self.architectures = archs.components(separatedBy: .whitespaces)
        } else {
            self.architectures = ["arm64", "armv7"]
        }

        self.sysroot = URL(fileURLWithPath: try Command.tryExec("/usr/bin/xcrun", ["-sdk", "iphoneos", "--show-sdk-path"]))
    
        if let dtPrefix = environment["DEPLOYMENT_TARGET_CLANG_PREFIX"], let dtName = environment["DEPLOYMENT_TARGET_CLANG_ENV_NAME"], let dt = environment[dtName] {
            self.deploymentTarget = dtPrefix + dt
        } else {
            self.deploymentTarget = "-miphoneos-version-min=9.0"
        }

        self.env = [
            "CC": try Command.tryExec("/usr/bin/xcrun", ["-find", "clang"]),
            "CXX": try Command.tryExec("/usr/bin/xcrun", ["-find", "clang++"]),
            "AR": try Command.tryExec("/usr/bin/xcrun", ["-find", "ar"]),
            "RANLIB": try Command.tryExec("/usr/bin/xcrun", ["-find", "ranlib"]),
            "PKGROOT": self.packageRoot.path,
            "SRCROOT": self.sourceRoot.path,
            "SDKROOT": self.sysroot.path,
            "BUILDROOT": self.buildRoot.path
        ]

        try self.setup()
    }

    fileprivate func setup() throws {
    }

    func build() throws {
        var archOutputs: [String: URL] = [:]
        for arch in architectures {
            print("Configuring for architecture: \(arch)")

            let outputForArch = buildProducts.appendingPathComponent(arch)

            let configureOutput = outputForArch.appendingPathComponent("configure")
            let buildOutput = outputForArch.appendingPathComponent("build")
            archOutputs[arch] = buildOutput

            // Don't build if already exists
            var hasBuilt = true
            for libraryName in self.package.libraryOutputs ?? [] {
                if !FileManager.default.fileExists(atPath: self.path(ofLibrary: libraryName, inBuildRoot: buildOutput).path) {
                    hasBuilt = false
                }
            }
            if hasBuilt {
                print("Already built all libraries for architecture: \(arch).")
                continue
            }

            try FileManager.default.createDirectory(atPath: configureOutput.path, withIntermediateDirectories: true, attributes: nil)
            try FileManager.default.createDirectory(atPath: buildOutput.path, withIntermediateDirectories: true, attributes: nil)

            try self.configure(
                architecture: arch, 
                inURL: configureOutput,
                buildOutputURL: buildOutput
            )
            try self.make(
                fromURL: configureOutput
            )
            try self.install(
                fromURL: configureOutput
            )
        }

        // Copy headers and pkgconfig
        if let arch = architectures.first {
            let archOutput = archOutputs[arch]!
            try self.copyHeadersAndMetadata(fromURL: archOutput, toURL: buildRoot)
        }

        // LIPO to create fat binary for each library
        let libRoot = buildRoot.appendingPathComponent("lib")
        try FileManager.default.createDirectory(atPath: libRoot.path, withIntermediateDirectories: true, attributes: nil)
        for libraryName in self.package.libraryOutputs ?? [] {
            try self.lipo(
                from: architectures.map { arch in
                    return (arch, self.path(ofLibrary: libraryName, inBuildRoot: archOutputs[arch]!))
                }, 
                toURL: self.path(ofLibrary: libraryName, inBuildRoot: buildRoot)
            )
        }
    }

    fileprivate func configure(architecture: String, inURL url: URL, buildOutputURL: URL) throws {}

    fileprivate func make(fromURL url: URL) throws {}

    fileprivate func install(fromURL url: URL) throws {}

    fileprivate func lipo(from architectureMap: [(architecture: String, url: URL)], toURL: URL) throws {
        print("Merging libraries \(architectureMap) to fat library at \(toURL)")
        var args = ["-create", "-output", toURL.path]
        for (arch, url) in architectureMap {
            args += ["-arch", arch, url.path]
        }

        try Command.trySpawn(
            "/usr/bin/lipo",
            args
        )
    }

    fileprivate func copyHeadersAndMetadata(fromURL url: URL, toURL: URL) throws {
        // Copy headers
        let headersRoot = buildRoot.appendingPathComponent("include")
        try FileManager.default.createDirectory(atPath: headersRoot.path, withIntermediateDirectories: true, attributes: nil)
        try Command.trySpawn(
            "/bin/cp",
            ["-R", url.appendingPathComponent("include").path, toURL.path]
        )

        // Copy pkgconfig
        let libRoot = toURL.appendingPathComponent("lib")
        let pkgconfigRoot = libRoot.appendingPathComponent("pkgconfig")
        try FileManager.default.createDirectory(atPath: pkgconfigRoot.path, withIntermediateDirectories: true, attributes: nil)
        try Command.trySpawn(
            "/bin/cp",
            ["-R", url.appendingPathComponent("lib").appendingPathComponent("pkgconfig").path, libRoot.path]
        )
        // Replace arch output path with new path for each file
        for path in try FileManager.default.contentsOfDirectory(at: pkgconfigRoot, includingPropertiesForKeys: nil, options: []) {
            try String(contentsOf: path).replacingOccurrences(of: url.path, with: toURL.path).write(to: path, atomically: true, encoding: .utf8)
        }
    }

    fileprivate func path(ofLibrary library: String, inBuildRoot buildRoot: URL) -> URL {
        return buildRoot.appendingPathComponent("lib").appendingPathComponent("\(library).a")
    }

    fileprivate func applyEnvToArgs(_ args: [String]) -> [String] {
        // Replace $#SOMETHING# with env[SOMETHING]
        let regex = try! NSRegularExpression(pattern: "\\$\\#([A-Z]*?)\\#", options: [])
        return args.map { arg in 
            var arg = arg
            for result in regex.matches(in: arg, range: NSMakeRange(0, arg.utf16.count)) {
                let range = result.range(at: 1)
                let key = (arg as NSString).substring(with: range)

                if let value = self.env[key] {
                    print("Replacing \(key) with \(value)")
                    arg = (arg as NSString).replacingCharacters(in: result.range(at: 0), with: self.env[key] ?? "")
                }
            }
            return arg
        }
    }
}

class MakeBuilder: Builder {

    override func setup() throws {
        try super.setup()
    }

    override func build() throws {
        print("Building package \(package.name) with make...")
        try super.build()
    }

    override func configure(architecture: String, inURL url: URL, buildOutputURL: URL) throws {
        let configureScript = self.sourceRoot.appendingPathComponent("configure")

        var args = [
            "-arch \(architecture)",
            "-isysroot \(self.sysroot.path)",
            "\(self.deploymentTarget)",
            "-fembed-bitcode",
            "--prefix=\(buildOutputURL.path)"
        ]
        if let packageArgs = self.package.buildArgs {
            args = packageArgs + args
        }
        if let packageArchSpecificArgs = self.package.buildArchSpecificArgs?["iphoneos"]?[architecture] {
            args = packageArchSpecificArgs + args
        }

        args = applyEnvToArgs(args)

        print("Running \(configureScript.path) with arguments: \(args)")

        try Command.trySpawn(
            configureScript.path,
            currentDirectory: url.path,
            env: self.env,
            args
        )
    }

    override func make(fromURL url: URL) throws {
        let processorCount = ProcessInfo.processInfo.processorCount
        try Command.trySpawn(
            "/usr/bin/make",
            currentDirectory: url.path,
            [
                "-j\(processorCount)"
            ]
        )
    }

    override func install(fromURL url: URL) throws {
        try Command.trySpawn(
            "/usr/bin/make",
            currentDirectory: url.path,
            [
                self.package.installCommand ?? "install"
            ]
        )
    }
}

class CMakeBuilder: Builder {

    override func setup() throws {
        try super.setup()
    }

    override func build() throws {
        print("Building package \(package.name) with CMake...")
        try super.build()
    }

    override func configure(architecture: String, inURL url: URL, buildOutputURL: URL) throws {

        var args = [
            "-DCMAKE_C_FLAGS=\(self.deploymentTarget) -fembed-bitcode",
            "-DCMAKE_INSTALL_PREFIX=\(buildOutputURL.path)",
            "-DCMAKE_OSX_SYSROOT=\(self.sysroot.path)",
            "-DCMAKE_OSX_ARCHITECTURES=\(architecture)",
            "-DCMAKE_PREFIX_PATH=\(self.buildProducts.path)",
            "-DPKG_CONFIG_USE_CMAKE_PREFIX_PATH=ON"
        ]
        if let packageArgs = self.package.buildArgs {
            args = args + packageArgs
        }
        if let packageArchSpecificArgs = self.package.buildArchSpecificArgs?["iphoneos"]?[architecture] {
            args = args + packageArchSpecificArgs
        }

        args = applyEnvToArgs(args)

        // Repository url
        args = args + [self.sourceRoot.path]

        print("Running CMake with arguments: \(args)")

        try Command.trySpawn(
            "/usr/local/bin/cmake",
            currentDirectory: url.path,
            env: self.env,
            args
        )
    }

    override func make(fromURL url: URL) throws {
        let processorCount = ProcessInfo.processInfo.processorCount
        try Command.trySpawn(
            "/usr/bin/make",
            currentDirectory: url.path,
            [
                "-j\(processorCount)"
            ]
        )
    }

    override func install(fromURL url: URL) throws {
        try Command.trySpawn(
            "/usr/bin/make",
            currentDirectory: url.path,
            [
                self.package.installCommand ?? "install"
            ]
        )
    }
}