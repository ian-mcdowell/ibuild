import Foundation

enum BuilderError: LocalizedError {
    case packageNotFound(String)

    var errorDescription: String? {
        switch self {
            case .packageNotFound(let name): return "Builder could not be created, because the package to build (\(name)) was not found."
        }
    }
}

class Builder {

    let packageName: String
    let buildProperties: Package.BuildProperties
    let env: [String: String]

    let architecture: String
    let platformName: String
    /// Root of the package that's building the library
    let packageRoot: URL
    /// Root of the library to be built
    let sourceRoot: URL
    let buildProductsRoot: URL
    let buildProducts: URL
    let sysroot: URL
    let deploymentTarget: String

    let configureOutput: URL
    let buildOutput: URL

    required init(buildProperties: Package.BuildProperties, packageName: String, packageRoot: URL, sourceRoot: URL, buildProductsRoot: URL, buildIntermediatesRoot: URL, architecture: String) throws {
        self.buildProperties = buildProperties
        self.packageName = packageName
        self.packageRoot = packageRoot
        self.sourceRoot = sourceRoot
        self.buildProductsRoot = buildProductsRoot
        self.architecture = architecture

        let environment = ProcessInfo.processInfo.environment
        if let tmpDir = environment["CONFIGURATION_TEMP_DIR"] {
            self.buildProducts = URL(fileURLWithPath: tmpDir).appendingPathComponent(sourceRoot.lastPathComponent).appendingPathComponent(architecture)
        } else {
            self.buildProducts = buildIntermediatesRoot.appendingPathComponent(sourceRoot.lastPathComponent).appendingPathComponent(architecture)
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

        self.configureOutput = self.buildProducts.appendingPathComponent("configure")
        self.buildOutput = self.buildProducts.appendingPathComponent("build")

        self.env = [
            "CC": try Command.tryExec("/usr/bin/xcrun", ["-find", "clang"]),
            "CPP": try Command.tryExec("/usr/bin/xcrun", ["-find", "clang"]),
            "CXX": try Command.tryExec("/usr/bin/xcrun", ["-find", "clang++"]),
            "LD": try Command.tryExec("/usr/bin/xcrun", ["-find", "ld"]),
            "AR": try Command.tryExec("/usr/bin/xcrun", ["-find", "ar"]),
            "RANLIB": try Command.tryExec("/usr/bin/xcrun", ["-find", "ranlib"]),
            "LIBTOOL": try Command.tryExec("/usr/bin/xcrun", ["-find", "libtool"]),
            "ARCH": architecture,
            "PKGROOT": self.packageRoot.path,
            "SRCROOT": self.sourceRoot.path,
            "SDKROOT": self.sysroot.path,
            "BUILDROOT": self.buildProductsRoot.path,
            "PKG_CONFIG_PATH": self.buildProductsRoot.appendingPathComponent("lib").appendingPathComponent("pkgconfig").path
        ]

        try self.setup()
    }

    fileprivate func setup() throws {
    }

    func build() throws {

        print("\t > Configuring \(packageName) for architecture: \(architecture)")

        try FileManager.default.createDirectory(atPath: configureOutput.path, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.createDirectory(atPath: buildOutput.path, withIntermediateDirectories: true, attributes: nil)

        try self.configure(
            architecture: architecture,
            inURL: configureOutput,
            buildOutputURL: buildOutput
        )
        try self.make(
            fromURL: configureOutput,
            buildOutputURL: buildOutput
        )
        try self.install(
            fromURL: configureOutput,
            toURL: buildOutput
        )
    }

    fileprivate func configure(architecture: String, inURL url: URL, buildOutputURL: URL) throws {}

    fileprivate func make(fromURL url: URL, buildOutputURL: URL) throws {}

    fileprivate func install(fromURL url: URL, toURL: URL) throws {}

    fileprivate func applyEnvToArgs(_ args: [String], _ additionalEnv: [String: String] = [:]) -> [String] {
        let env = self.env.merging(additionalEnv) { (_, additional) in additional }

        // Replace $#SOMETHING# with env[SOMETHING]
        let regex = try! NSRegularExpression(pattern: "\\$\\#([A-Z]*?)\\#", options: [])
        return args.map { arg in 
            var arg = arg
            while let result = regex.matches(in: arg, range: NSMakeRange(0, arg.utf16.count)).first {
                let range = result.range(at: 1)
                let key = (arg as NSString).substring(with: range)

                let value = env[key] ?? ""
                arg = (arg as NSString).replacingCharacters(in: result.range(at: 0), with: value)
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
        if let packageArgs = self.buildProperties.buildArgs {
            args = packageArgs + args
        }
        if let packageArchSpecificArgs = self.buildProperties.buildArchSpecificArgs?[self.platformName]?[architecture] {
            args = packageArchSpecificArgs + args
        }

        args = applyEnvToArgs(args)

        print("\t > Running configure with arguments: \(args.joined(separator: " "))")

        try Command.trySpawn(
            configureScript.path,
            currentDirectory: url.path,
            env: self.env,
            args
        )
    }

    override func make(fromURL url: URL, buildOutputURL: URL) throws {
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
                self.buildProperties.installCommand ?? "install"
            ]
        )
    }
}

class CMakeBuilder: Builder {

    override func setup() throws {
        try super.setup()
    }

    override func build() throws {
        try super.build()
    }

    override func configure(architecture: String, inURL url: URL, buildOutputURL: URL) throws {

        var args = [
            "-DCMAKE_C_FLAGS=\(self.deploymentTarget) -fembed-bitcode",
            "-DCMAKE_INSTALL_PREFIX=\(buildOutputURL.path)",
            "-DCMAKE_OSX_SYSROOT=\(self.sysroot.path)",
            "-DCMAKE_OSX_ARCHITECTURES=\(architecture)",
            "-DCMAKE_PREFIX_PATH=\(self.buildProductsRoot.path)",
            "-DPKG_CONFIG_USE_CMAKE_PREFIX_PATH=ON"
        ]
        if let packageArgs = self.buildProperties.buildArgs {
            args += packageArgs
        }
        if let packageArchSpecificArgs = self.buildProperties.buildArchSpecificArgs?[self.platformName]?[architecture] {
            args += packageArchSpecificArgs
        }

        args = applyEnvToArgs(args)

        // Repository url
        args += [self.sourceRoot.path]

        print("\t > Running CMake with arguments: \(args)")

        try Command.trySpawn(
            "/usr/local/bin/cmake",
            currentDirectory: url.path,
            env: self.env,
            args
        )
    }

    override func make(fromURL url: URL, buildOutputURL: URL) throws {
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
                self.buildProperties.installCommand ?? "install"
            ]
        )
    }
}

class XcodeBuilder: Builder {

    override func configure(architecture: String, inURL url: URL, buildOutputURL: URL) throws {

        let environment = ProcessInfo.processInfo.environment

        let deploymentTarget: String?
        if let deploymentTargetName = environment["DEPLOYMENT_TARGET_SETTING_NAME"], let value = environment[deploymentTargetName] {
            deploymentTarget = "\(deploymentTargetName)=\(value)"
        } else if let value = environment["IPHONEOS_DEPLOYMENT_TARGET"] {
            deploymentTarget = "IPHONEOS_DEPLOYMENT_TARGET=\(value)"
        } else {
            deploymentTarget = nil
        }
        var args = [
            "install",
            "-sdk", self.sysroot.path,
            "-arch", architecture,
            "OBJROOT=\(buildOutputURL.path)",
            "SYMROOT=\(buildOutputURL.path)",
            "DSTROOT=\(buildOutputURL.path)",
            "ONLY_ACTIVE_ARCH=YES",
            "IBUILD_CURRENT_BUILD_ROOT=\(self.buildProductsRoot.path)",
            "IBUILD_CURRENT_PACKAGE_ROOT=\(packageRoot.path)"
        ]
        if let deploymentTarget = deploymentTarget {
            args += [deploymentTarget]
        }
        if let packageArgs = self.buildProperties.buildArgs {
            args += packageArgs
        }
        if let packageArchSpecificArgs = self.buildProperties.buildArchSpecificArgs?[self.platformName]?[architecture] {
            args += packageArchSpecificArgs
        }
        try Command.trySpawn(
            "/usr/bin/xcodebuild",
            currentDirectory: self.sourceRoot.path,
            args
        )
    }

    override func install(fromURL url: URL, toURL: URL) throws {
        let platformName = self.platformName.replacingOccurrences(of: ".internal", with: "")
        let xcodeOutputURL = toURL.appendingPathComponent("Release-\(platformName)")

        for libraryName in self.buildProperties.outputs ?? [] {
            try Command.cp(from: xcodeOutputURL.appendingPathComponent(libraryName), to: toURL)
        }

        // Copy swiftmodule(s)
        let swiftmoduleURL = toURL.appendingPathComponent("swiftmodules")
        for path in try FileManager.default.contentsOfDirectory(at: xcodeOutputURL, includingPropertiesForKeys: nil, options: []) {
            if path.pathExtension == "swiftmodule" {
                try FileManager.default.createDirectory(atPath: swiftmoduleURL.path, withIntermediateDirectories: true, attributes: nil)
                try Command.cp(from: path, to: swiftmoduleURL.appendingPathComponent(path.lastPathComponent))
            }
        }
    }
}

class CustomBuilder: Builder {

    override func configure(architecture: String, inURL url: URL, buildOutputURL: URL) throws {
        // ENV: prefix, chost, srcroot
        // Applies to: configure/make/install/env, buildArgs

        guard let configureProperty = buildProperties.customProperties?.configure else { return }

        var (configure, args) = extractArgs(forCommand: configureProperty)

        var env = [
            "ARCH": architecture,
            "PREFIX": buildOutputURL.path
        ]
        env = self.customEnv(env)

        configure = launchPath(forCommand: applyEnv(configure, env))

        if let packageArgs = self.buildProperties.buildArgs {
            args = packageArgs + args
        }
        if let packageArchSpecificArgs = self.buildProperties.buildArchSpecificArgs?[self.platformName]?[architecture] {
            args = packageArchSpecificArgs + args
        }
        args = applyEnv(args, env)

        print("\t > Running custom configure script: \(configure) \(args)")
        try Command.trySpawn(
            configure,
            currentDirectory: self.sourceRoot.path,
            env: env,
            args
        )
    }

    override func make(fromURL url: URL, buildOutputURL: URL) throws {
        guard let makeProperty = buildProperties.customProperties?.make else { return }

        var env: [String: String] = [
            "PREFIX": buildOutputURL.path
        ]
        env = self.customEnv(env)

        var (make, args) = extractArgs(forCommand: makeProperty)
        make = launchPath(forCommand: applyEnv(make, env))
        args = applyEnv(args, env)

        print("\t > Running custom make command: \(install) \(args)")
        try Command.trySpawn(
            make,
            currentDirectory: self.sourceRoot.path,
            env: env,
            args
        )
    }

    override func install(fromURL url: URL, toURL: URL) throws {
        guard let installProperty = buildProperties.customProperties?.install else { return }

        var env = [
            "PREFIX": toURL.path
        ]
        env = self.customEnv(env)

        var (install, args) = extractArgs(forCommand: installProperty)
        install = launchPath(forCommand: applyEnv(install, env))
        args = applyEnv(args, env)

        print("\t > Running custom install command: \(install) \(args)")
        try Command.trySpawn(
            install,
            currentDirectory: self.sourceRoot.path,
            env: env,
            args
        )
    }

    private func extractArgs(forCommand command: String) -> (command: String, args: [String]) {
        var components = command.components(separatedBy: .whitespaces)
        let command = components.removeFirst()
        return (command, components)
    }

    private func launchPath(forCommand command: String) -> String {
        if command.hasPrefix("/") { return command }
        return self.sourceRoot.appendingPathComponent(command).path
    }

    private func applyEnv(_ value: String, _ env: [String: String]) -> String {
        return applyEnv([value], env).first!
    }

    private func applyEnv(_ values: [String], _ env: [String: String]) -> [String] {
        return self.applyEnvToArgs(values, env)
    }

    private func customEnv(_ env: [String: String]) -> [String: String] {
        // Apply env to the provided env if exists
        let customEnvironment: [String: String]
        if var customEnv = buildProperties.customProperties?.env {
            customEnv = customEnv.mapValues { self.applyEnvToArgs([$0], env).first! }
            customEnvironment = customEnv.merging(env) { (keep, _) in keep }
        } else {
            customEnvironment = env
        }
        return self.env.merging(customEnvironment) { (_, keep) in keep }
    }
}
