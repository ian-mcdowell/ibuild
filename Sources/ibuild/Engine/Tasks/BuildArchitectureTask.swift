import llbuildSwift
import Foundation

class BuildArchitectureRule: PackageRuleProtocol {
    let package: Package
    let packageURL: URL
    let buildSystem: BuildSystem
    let architecture: String
    let sourceRoot: URL

    required init(package: Package, packageURL: URL, parameters: [String], buildSystem: BuildSystem) {
        self.package = package
        self.packageURL = packageURL
        self.buildSystem = buildSystem
        self.architecture = parameters[0]
        self.sourceRoot = URL(fileURLWithPath: parameters[1])
    }

    func isResultValid(_ priorValue: Value) -> Bool {
        let libraryOutputs = package.build?.outputs ?? []
        let priorPath = priorValue.toString()
        if priorPath.isEmpty {
            return false
        }
        let outputURL = URL(fileURLWithPath: priorPath)

        let fileManager = FileManager.default
        for output in libraryOutputs {
            if !fileManager.fileExists(atPath: outputURL.appendingPathComponent(output).path) {
                return false
            }
        }
        return true
    }

    func createTask() -> Task {
        return BuildArchitectureTask(rule: self)
    }

    class BuildArchitectureTask: Task {
        let rule: BuildArchitectureRule

        init(rule: BuildArchitectureRule) {
            self.rule = rule
        }

        func start(_ engine: TaskBuildEngine) {

        }

        func provideValue(_ engine: TaskBuildEngine, inputID: Int, value: Value) {

        }

        func inputsAvailable(_ engine: TaskBuildEngine) {
            let rule = self.rule

            guard let buildProperties = rule.package.build else {
                return engine.taskIsComplete(Value(""), forceChange: false)
            }

            print("Building \(rule.package.name) \(rule.architecture)")

            let builderClass: Builder.Type
            switch buildProperties.buildSystem {
            case .cmake: builderClass = CMakeBuilder.self
            case .make: builderClass = MakeBuilder.self
            case .xcode: builderClass = XcodeBuilder.self
            case .custom: builderClass = CustomBuilder.self
            }

            DispatchQueue.global().async {
                do {
                    let builder = try builderClass.init(buildProperties: buildProperties, packageName: rule.package.name, packageRoot: rule.packageURL, sourceRoot: rule.sourceRoot, buildProductsRoot: rule.buildSystem.buildProductsRoot, buildIntermediatesRoot: rule.buildSystem.buildIntermediatesRoot, architecture: rule.architecture)

                    try builder.build()

                    engine.taskIsComplete(Value(builder.buildOutput.path), forceChange: false)
                } catch {
                    print("Failure building: \(error.localizedDescription)")
                    engine.taskIsComplete(Value(""), forceChange: false)
                }
            }
        }
    }
}
