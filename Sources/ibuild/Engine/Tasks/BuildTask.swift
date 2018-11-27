import llbuildSwift
import Foundation

/// Run build commands per architecture, returning JSON dictionary [arch: value]
class BuildRule: PackageRuleProtocol {

    let package: Package
    let packageURL: URL
    let buildSystem: BuildSystem
    let sourceRoot: URL
    let architectures: [String]

    required init(package: Package, packageURL: URL, parameters: [String], buildSystem: BuildSystem) {
        self.package = package
        self.packageURL = packageURL
        self.buildSystem = buildSystem
        self.sourceRoot = URL(fileURLWithPath: parameters[0])

        let environment = ProcessInfo.processInfo.environment
        if let archs = environment["ARCHS"] {
            self.architectures = archs.components(separatedBy: .whitespaces)
        } else {
            self.architectures = ["arm64"]
        }
    }

    func isResultValid(_ priorValue: Value) -> Bool {
        return false
    }

    func createTask() -> Task {
        return BuildTask(rule: self)
    }

    class BuildTask: Task {
        let rule: BuildRule

        init(rule: BuildRule) {
            self.rule = rule
        }

        var result: [String: URL] = [:]

        func start(_ engine: TaskBuildEngine) {

            // Skip build if running in Xcode and trying to build current project
            let environment = ProcessInfo.processInfo.environment
            if rule.package.build?.buildSystem == .xcode,
                let projectDir = environment["PROJECT_DIR"],
                rule.packageURL == URL(fileURLWithPath: projectDir) {
                return
            }

            for (index, architecture) in rule.architectures.enumerated() {
                engine.taskNeedsInput(rule.buildSystem.keyForBuildingArchitecture(architecture, sourceRoot: rule.sourceRoot, atFileURL: rule.packageURL), inputID: index)
            }
        }

        func provideValue(_ engine: TaskBuildEngine, inputID: Int, value: Value) {
            let arch = rule.architectures[inputID]
            result[arch] = URL(fileURLWithPath: value.toString())
        }

        func inputsAvailable(_ engine: TaskBuildEngine) {

            if let firstResult = result.values.first {
                // Copy headers and pkgconfig
                do {
                    try self.copyHeadersAndMetadata(fromURL: firstResult, toURL: rule.buildSystem.buildProductsRoot)
                } catch {
                    print("Failed to copy extra files: \(error.localizedDescription)")
                }

                // Run lipo
                lipo()
            }

            engine.taskIsComplete(Value(""), forceChange: false)
        }

        fileprivate func copyHeadersAndMetadata(fromURL url: URL, toURL: URL) throws {
            try FileManager.default.createDirectory(atPath: toURL.path, withIntermediateDirectories: true, attributes: nil)

            // Copy headers
            let headersURL = url.appendingPathComponent("include")
            if FileManager.default.fileExists(atPath: headersURL.path) {
                let headersRoot = toURL.appendingPathComponent("include")
                try FileManager.default.createDirectory(atPath: headersRoot.path, withIntermediateDirectories: true, attributes: nil)
                try Command.cp(from: headersURL, to: toURL)
            }

            // Copy pkgconfig
            let pkgconfigURL = url.appendingPathComponent("lib").appendingPathComponent("pkgconfig")
            if FileManager.default.fileExists(atPath: pkgconfigURL.path) {
                let libRoot = toURL.appendingPathComponent("lib")
                let pkgconfigRoot = libRoot.appendingPathComponent("pkgconfig")
                try FileManager.default.createDirectory(atPath: pkgconfigRoot.path, withIntermediateDirectories: true, attributes: nil)
                try Command.cp(from: pkgconfigURL, to: libRoot)

                // Replace arch output path with new path for each file
                for path in try FileManager.default.contentsOfDirectory(at: pkgconfigRoot, includingPropertiesForKeys: nil, options: []) {
                    try String(contentsOf: path).replacingOccurrences(of: url.path, with: toURL.path).write(to: path, atomically: true, encoding: .utf8)
                }
            }

            // Copy swiftmodules
            let swiftmoduleURL = url.appendingPathComponent("swiftmodules")
            if FileManager.default.fileExists(atPath: swiftmoduleURL.path) {
                try Command.cp(from: swiftmoduleURL, to: toURL)
            }

            if let auxiliary = rule.package.build?.auxiliaryFiles {
                for (sourcePath, destinationPath) in auxiliary {
                    let destination = toURL.appendingPathComponent(destinationPath)
                    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
                    try Command.cp(from: rule.packageURL.appendingPathComponent(sourcePath), to: destination)
                }
            }
        }

        private func lipo() {
            let outputs = rule.package.build?.outputs ?? []

            // LIPO to create fat binary for each library
            for libraryName in outputs {

                do {
                    if libraryName.hasSuffix(".a") || libraryName.hasSuffix(".dylib") || libraryName.hasSuffix(".framework") {

                        let archMap = rule.architectures.map { arch in
                            return (arch, result[arch]!.appendingPathComponent(libraryName))
                        }

                        let libraryURL = rule.buildSystem.buildProductsRoot.appendingPathComponent(libraryName)
                        if !FileManager.default.fileExists(atPath: libraryURL.path) {
                            try self.lipo(
                                from: archMap,
                                toURL: libraryURL
                            )
                        }
                    } else {
                        if let firstArchitecture = rule.architectures.first, let url = result[firstArchitecture] {
                            let destination = rule.buildSystem.buildProductsRoot.appendingPathComponent(libraryName)
                            try FileManager.default.createDirectory(atPath: destination.deletingLastPathComponent().path, withIntermediateDirectories: true, attributes: nil)
                            try Command.cp(from: url.appendingPathComponent(libraryName), to: destination)
                        }
                    }
                } catch {
                    print("Lipo failed: \(error.localizedDescription)")
                }
            }
        }

        fileprivate func lipo(from architectureMap: [(architecture: String, url: URL)], toURL: URL) throws {

            if toURL.pathExtension == "framework" {
                // Special behavior for frameworks:
                // - Copy framework from first architecture
                // - Lipo FrameworkName.framework/FrameworkName binary.
                // - Copy swiftmodules from FrameworkName.framework/Modules/FrameworkName.swiftmodule

                if let firstArchitecture = architectureMap.first?.url {
                    try Command.cp(from: firstArchitecture, to: toURL.deletingLastPathComponent())
                }

                let binaryName = toURL.deletingPathExtension().lastPathComponent
                let binaryArchitectureMap = architectureMap.map { (architecture: $0.architecture, url: $0.url.appendingPathComponent(binaryName)) }
                let binaryToURL = toURL.appendingPathComponent(binaryName)
                try _lipo(from: binaryArchitectureMap, toURL: binaryToURL)

                for arch in architectureMap {
                    let swiftmodule = arch.url.appendingPathComponent("Modules").appendingPathComponent("\(binaryName).swiftmodule")
                    if FileManager.default.fileExists(atPath: swiftmodule.path) {
                        try Command.cp(from: swiftmodule, to: toURL.appendingPathComponent("Modules"))
                    }
                }
            } else {
                try _lipo(from: architectureMap, toURL: toURL)
            }
        }

        private func _lipo(from architectureMap: [(architecture: String, url: URL)], toURL: URL) throws {

            try FileManager.default.createDirectory(atPath: toURL.deletingLastPathComponent().path, withIntermediateDirectories: true, attributes: nil)

            print("\t > Merging libraries \(architectureMap) to fat library at \(toURL)")
            var args = ["-create", "-output", toURL.path]
            for (arch, url) in architectureMap {
                args += ["-arch", arch, url.path]
            }

            try Command.trySpawn(
                "/usr/bin/lipo",
                args
            )
        }
    }
}
