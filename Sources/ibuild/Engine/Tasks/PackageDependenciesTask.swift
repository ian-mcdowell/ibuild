import llbuildSwift
import Foundation

class PackageDependenciesRule: PackageRuleProtocol {
    let buildSystem: BuildSystem
    let locations: [Package.Location]

    required init(package: Package, packageURL: URL, parameters: [String], buildSystem: BuildSystem) {
        self.locations = package.dependencies ?? []
        self.buildSystem = buildSystem
    }

    func isResultValid(_ priorValue: Value) -> Bool {
        return false
    }

    func createTask() -> Task {
        return PackageDependenciesTask(rule: self)
    }

    class PackageDependenciesTask: Task {
        let rule: PackageDependenciesRule

        init(rule: PackageDependenciesRule) {
            self.rule = rule
        }

        func start(_ engine: TaskBuildEngine) {
            for (index, location) in rule.locations.enumerated() {
                engine.taskNeedsInput(rule.buildSystem.keyForPackage(location), inputID: index)
            }
        }

        func provideValue(_ engine: TaskBuildEngine, inputID: Int, value: Value) {
            
        }

        func inputsAvailable(_ engine: TaskBuildEngine) {
            engine.taskIsComplete(Value(""), forceChange: false)
        }
    }
}
