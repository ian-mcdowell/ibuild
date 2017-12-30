import Foundation

class Builder {
    static func forPackage(_ package: Package, projectSourceMap: ProjectSourceMap, buildRoot: URL) throws -> Builder? {
        let packageRoot = URL(fileURLWithPath: projectSourceMap.locations[package.url]!)
        let sourceRoot: URL
        if let library = package.library {
            sourceRoot = URL(fileURLWithPath: projectSourceMap.locations[library.url]!)
        } else {
            sourceRoot = packageRoot
        }
        let builderClass: Builder.Type
        switch package.buildSystem {
            case .none: return nil
            case .cmake: builderClass = CMakeBuilder.self 
            case .make: builderClass = MakeBuilder.self 
            case .xcode: builderClass = XcodeBuilder.self 
        }
        return try builderClass.init(package: package, packageRoot: packageRoot, sourceRoot: sourceRoot, buildRoot: buildRoot)
    }

    let package: Package
    let env: [String: String]

    let architectures: [String]
    let platformName: String
    /// Root of the package that's building the library
    let packageRoot: URL
    /// Root of the library to be built
    let sourceRoot: URL
    let buildRoot: URL
    let buildProducts: URL
    let sysroot: URL
    let deploymentTarget: String

    required init(package: Package, packageRoot: URL, sourceRoot: URL, buildRoot: URL) throws {
        self.package = package
        self.packageRoot = packageRoot
        self.sourceRoot = sourceRoot
        self.buildRoot = buildRoot

        let environment = ProcessInfo.processInfo.environment
        self.buildProducts = buildRoot.appendingPathComponent("products").appendingPathComponent(sourceRoot.lastPathComponent)

        if let archs = environment["ARCHS"] {
            self.architectures = archs.components(separatedBy: .whitespaces)
        } else {
            self.architectures = ["arm64"]
        }
        if let platformName = environment["PLATFORM_NAME"] {
            self.platformName = platformName
        } else {
            self.platformName = "iphoneos"
        }

        self.sysroot = URL(fileURLWithPath: try Command.tryExec("/usr/bin/xcrun", ["-sdk", self.platformName, "--show-sdk-path"]))
    
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
        guard let libraryOutputs = self.package.libraryOutputs else {
            print("No library outputs. Skipping build.")
            return
        }

        var archOutputs: [String: URL] = [:]
        for arch in architectures {
            print("Configuring for architecture: \(arch)")

            let outputForArch = buildProducts.appendingPathComponent(arch)

            let configureOutput = outputForArch.appendingPathComponent("configure")
            let buildOutput = outputForArch.appendingPathComponent("build")
            archOutputs[arch] = buildOutput

            // Don't build if already exists
            var hasBuilt = true
            for libraryName in libraryOutputs {
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
                fromURL: configureOutput,
                toURL: buildOutput
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
        for libraryName in libraryOutputs {
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

    fileprivate func install(fromURL url: URL, toURL: URL) throws {}

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
        let headersURL = url.appendingPathComponent("include")
        if FileManager.default.fileExists(atPath: headersURL.path) {
            let headersRoot = buildRoot.appendingPathComponent("include")
            try FileManager.default.createDirectory(atPath: headersRoot.path, withIntermediateDirectories: true, attributes: nil)
            try Command.trySpawn(
                "/bin/cp",
                ["-R", headersURL.path, toURL.path]
            )
        }

        // Copy pkgconfig
        let pkgconfigURL = url.appendingPathComponent("lib").appendingPathComponent("pkgconfig")
        if FileManager.default.fileExists(atPath: pkgconfigURL.path) {
            let libRoot = toURL.appendingPathComponent("lib")
            let pkgconfigRoot = libRoot.appendingPathComponent("pkgconfig")
            try FileManager.default.createDirectory(atPath: pkgconfigRoot.path, withIntermediateDirectories: true, attributes: nil)
            try Command.trySpawn(
                "/bin/cp",
                ["-R", pkgconfigURL.path, libRoot.path]
            )
            // Replace arch output path with new path for each file
            for path in try FileManager.default.contentsOfDirectory(at: pkgconfigRoot, includingPropertiesForKeys: nil, options: []) {
                try String(contentsOf: path).replacingOccurrences(of: url.path, with: toURL.path).write(to: path, atomically: true, encoding: .utf8)
            }
        }

        // Copy swiftmodules
        let swiftmoduleURL = url.appendingPathComponent("swiftmodules")
        if FileManager.default.fileExists(atPath: swiftmoduleURL.path) {
            try Command.trySpawn(
                "/bin/cp",
                ["-R", swiftmoduleURL.path, toURL.path]
            )
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
        if let packageArchSpecificArgs = self.package.buildArchSpecificArgs?[self.platformName]?[architecture] {
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

    override func install(fromURL url: URL, toURL: URL) throws {
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
            "-DCMAKE_PREFIX_PATH=\(self.buildRoot.path)",
            "-DPKG_CONFIG_USE_CMAKE_PREFIX_PATH=ON"
        ]
        if let packageArgs = self.package.buildArgs {
            args = args + packageArgs
        }
        if let packageArchSpecificArgs = self.package.buildArchSpecificArgs?[self.platformName]?[architecture] {
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

    override func install(fromURL url: URL, toURL: URL) throws {
        try Command.trySpawn(
            "/usr/bin/make",
            currentDirectory: url.path,
            [
                self.package.installCommand ?? "install"
            ]
        )
    }
}

class XcodeBuilder: Builder {

    override func configure(architecture: String, inURL url: URL, buildOutputURL: URL) throws {

        let environment = ProcessInfo.processInfo.environment

        let deploymentTarget: String
        if let deploymentTargetName = environment["DEPLOYMENT_TARGET_SETTING_NAME"], let value = environment[deploymentTargetName] {
            deploymentTarget = "\(deploymentTargetName)=\(value)"
        } else if let value = environment["IPHONEOS_DEPLOYMENT_TARGET"] {
            deploymentTarget = "IPHONEOS_DEPLOYMENT_TARGET=\(value)"
        } else {
            deploymentTarget = "IPHONEOS_DEPLOYMENT_TARGET=9.0"
        }
        var args = [
            "build",
            "-sdk", self.sysroot.path,
            "-arch", architecture,
            deploymentTarget,
            "OBJROOT=\(buildOutputURL.path)",
            "SYMROOT=\(buildOutputURL.path)"
        ]
        if let packageArgs = self.package.buildArgs {
            args = args + packageArgs
        }
        if let packageArchSpecificArgs = self.package.buildArchSpecificArgs?[self.platformName]?[architecture] {
            args = args + packageArchSpecificArgs
        }
        try Command.trySpawn(
            "/usr/bin/xcodebuild",
            currentDirectory: self.sourceRoot.path,
            args
        )
    }

    override func install(fromURL url: URL, toURL: URL) throws {
        let libURL = toURL.appendingPathComponent("lib")
        let xcodeOutputURL = toURL.appendingPathComponent("Release-\(self.platformName)")

        try FileManager.default.createDirectory(atPath: libURL.path, withIntermediateDirectories: true, attributes: nil)

        for libraryName in self.package.libraryOutputs ?? [] {
            try Command.trySpawn(
                "/bin/cp",
                ["-R", xcodeOutputURL.appendingPathComponent(libraryName + ".a").path, libURL.path]
            )
        }

        // Copy swiftmodule(s)
        let swiftmoduleURL = toURL.appendingPathComponent("swiftmodules")
        for path in try FileManager.default.contentsOfDirectory(at: xcodeOutputURL, includingPropertiesForKeys: nil, options: []) {
            if path.pathExtension == "swiftmodule" {
                try FileManager.default.createDirectory(atPath: swiftmoduleURL.path, withIntermediateDirectories: true, attributes: nil)
                try Command.trySpawn(
                    "/bin/cp",
                    ["-R", path.path, swiftmoduleURL.appendingPathComponent(path.lastPathComponent).path]
                )
            }
        }
    }
}