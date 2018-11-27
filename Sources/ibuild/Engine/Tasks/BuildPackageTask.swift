import llbuildSwift
import Foundation

/// Builds and processes a package
class BuildPackageRule: PackageRuleProtocol {
    let package: Package
    let packageURL: URL
    let buildSystem: BuildSystem

    required init(package: Package, packageURL: URL, parameters: [String], buildSystem: BuildSystem) {
        self.package = package
        self.packageURL = packageURL
        self.buildSystem = buildSystem
    }

    func isResultValid(_ priorValue: Value) -> Bool {
        return false
    }
    
    func createTask() -> Task {
        return BuildPackageTask(rule: self)
    }

    class BuildPackageTask: Task {
        let rule: BuildPackageRule

        private struct InputID {
            static let download = 0
            static let build = 1
            static let copyHeaders = 2
            static let lipo = 3
        }

        init(rule: BuildPackageRule) {
            self.rule = rule
        }

        func start(_ engine: TaskBuildEngine) {
            guard let buildProperties = rule.package.build else {
                return
            }

            if let location = buildProperties.location {
                engine.taskNeedsInput(rule.buildSystem.keyForDownloadingLocation(location), inputID: InputID.download)
            } else {
                // Build root package
                engine.taskNeedsInput(rule.buildSystem.keyForBuilding(sourceRoot: rule.packageURL, atFileURL: rule.packageURL), inputID: InputID.build)
            }
        }

        func provideValue(_ engine: TaskBuildEngine, inputID: Int, value: Value) {
            if inputID == InputID.download {
                // Download complete, now build.
                let downloadedURL = URL(fileURLWithPath: value.toString())
                engine.taskNeedsInput(rule.buildSystem.keyForBuilding(sourceRoot: downloadedURL, atFileURL: rule.packageURL), inputID: InputID.build)
            } else if inputID == InputID.build {
                // Build complete
                print("Finished building package: \(rule.package.name)")
            }
        }

        func inputsAvailable(_ engine: TaskBuildEngine) {
            engine.taskIsComplete(Value(""), forceChange: false)
        }

        private static func applyPatches(_ patches: [String], in patchesURL: URL, to: URL) throws {
            print("\t > Applying patches: \(patches)")
            for patch in patches {
                try Command.tryExec("/usr/bin/patch", currentDirectory: to.path, ["-p", "1", "-i", patchesURL.appendingPathComponent(patch).path])
            }
        }
    }
}
