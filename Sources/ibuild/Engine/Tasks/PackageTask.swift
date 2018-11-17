import llbuildSwift
import Foundation

/// Root task for downloading and building a package
class PackageRule: LocationRuleProtocol {
    let location: Package.Location
    let buildSystem: BuildSystem

    required init(location: Package.Location, buildSystem: BuildSystem) {
        self.location = location
        self.buildSystem = buildSystem
    }

    func isResultValid(_ priorValue: Value) -> Bool {
        return false
    }

    func createTask() -> Task {
        return PackageTask(rule: self)
    }

    class PackageTask: Task {
        let rule: PackageRule

        var packageURL: URL?
        var buildValue: Value?

        private struct InputID {
            static let downloadPackage = 0
            static let buildDependencies = 1
            static let buildPackage = 2
        }

        init(rule: PackageRule) {
            self.rule = rule
        }

        func start(_ engine: TaskBuildEngine) {
            // Fetch contents of location using DownloadPackageLocation
            engine.taskNeedsInput(rule.buildSystem.keyForDownloadingLocation(rule.location), inputID: InputID.downloadPackage)
        }

        func provideValue(_ engine: TaskBuildEngine, inputID: Int, value: Value) {
            if inputID == InputID.downloadPackage {
                // Package was downloaded
                let downloadedURL = URL(fileURLWithPath: value.toString())
                packageURL = downloadedURL
                engine.taskNeedsInput(rule.buildSystem.keyForPackageDependencies(atFileURL: downloadedURL), inputID: InputID.buildDependencies)
            } else if inputID == InputID.buildDependencies {
                // Package dependencies were built
                guard let packageURL = packageURL else {
                    fatalError("Package URL missing once package dependencies were built")
                }
                engine.taskNeedsInput(rule.buildSystem.keyForBuildingPackage(atFileURL: packageURL), inputID: InputID.buildPackage)
            } else if inputID == InputID.buildPackage {
                // Package was built
                buildValue = value
            }
        }

        func inputsAvailable(_ engine: TaskBuildEngine) {
            guard let buildValue = buildValue else { fatalError("Package task inputs were available, but no value returned from build.") }
            engine.taskIsComplete(buildValue, forceChange: false)
        }
    }
}
