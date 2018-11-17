import llbuildSwift
import Foundation

protocol LocationRuleProtocol: Rule {
    init(location: Package.Location, buildSystem: BuildSystem)
}

protocol PackageRuleProtocol: Rule {
    init(package: Package, packageURL: URL, parameters: [String], buildSystem: BuildSystem)
}

/// Defines types of keys in the graph, and provides entities for creating keys
/// Maps a given key to a rule
/// Delegate of the build engine.
class BuildSystem: BuildEngineDelegate {

    /// /
    let packageRoot: URL

    /// /.ibuild/checkout
    let sourceRoot: URL

    /// /.ibuild/build/Products
    let buildProductsRoot: URL

    /// /.ibuild/build/Intermediates
    let buildIntermediatesRoot: URL

    private static let keySeparator = " | "
    private enum LocationRuleIdentifier: String {
        case package = "P"
        case downloadLocation = "DL"

        var ruleType: LocationRuleProtocol.Type {
            switch self {
            case .package: return PackageRule.self
            case .downloadLocation: return DownloadPackageLocationRule.self
            }
        }

        func key(for location: Package.Location) -> Key {
            let keySequence = [self.rawValue] + location.asKeySequence()
            return Key("<" + keySequence.joined(separator: BuildSystem.keySeparator) + ">")
        }
    }

    private enum PackageRuleIdentifier: String {
        case packageDependencies = "PD"
        case buildPackage = "BP"
        case build = "B"
        case buildArchitecture = "BA"

        var ruleType: PackageRuleProtocol.Type {
            switch self {
            case .packageDependencies: return PackageDependenciesRule.self
            case .buildPackage: return BuildPackageRule.self
            case .build: return BuildRule.self
            case .buildArchitecture: return BuildArchitectureRule.self
            }
        }

        func key(for fileURL: URL, parameters: [String]) -> Key {
            let keySequence = [self.rawValue, fileURL.path] + parameters
            return Key("<" + keySequence.joined(separator: BuildSystem.keySeparator) + ">")
        }
    }

    init(packageRoot: URL, sourceRoot: URL, buildProductsRoot: URL, buildIntermediatesRoot: URL) {
        self.packageRoot = packageRoot
        self.sourceRoot = sourceRoot
        self.buildProductsRoot = buildProductsRoot
        self.buildIntermediatesRoot = buildIntermediatesRoot
    }

    // MARK: Key retrieval

    func keyForPackage(_ location: Package.Location) -> Key {
        return LocationRuleIdentifier.package.key(for: location)
    }

    func keyForDownloadingLocation(_ location: Package.Location) -> Key {
        return LocationRuleIdentifier.downloadLocation.key(for: location)
    }

    func keyForPackageDependencies(atFileURL fileURL: URL) -> Key {
        return PackageRuleIdentifier.packageDependencies.key(for: fileURL, parameters: [])
    }

    func keyForBuildingPackage(atFileURL fileURL: URL) -> Key {
        return PackageRuleIdentifier.buildPackage.key(for: fileURL, parameters: [])
    }

    func keyForBuilding(sourceRoot: URL, atFileURL fileURL: URL) -> Key {
        return PackageRuleIdentifier.build.key(for: fileURL, parameters: [sourceRoot.path])
    }

    func keyForBuildingArchitecture(_ architecture: String, sourceRoot: URL, atFileURL fileURL: URL) -> Key {
        return PackageRuleIdentifier.buildArchitecture.key(for: fileURL, parameters: [architecture, sourceRoot.path])
    }


    // MARK: Key parsing


    // MARK: BuildEngineDelegate
    func lookupRule(_ key: Key) -> Rule {
        var str = key.toString()

        // Remove and validate first and last characters
        guard str.removeFirst() == "<" && str.removeLast() == ">" else {
            fatalError("Only virtual build system keys are supported.")
        }
        
        // Split by separator
        var keySequence = str.components(separatedBy: BuildSystem.keySeparator)
        guard let first = keySequence.first else {
            fatalError("No identifier found in sequence")
        }

        keySequence.removeFirst()

        do {
            if let identifier = LocationRuleIdentifier(rawValue: first) {
                let location = try Package.Location(from: keySequence)
                return identifier.ruleType.init(location: location, buildSystem: self)
            } else if let identifier = PackageRuleIdentifier(rawValue: first) {
                guard let path = keySequence.first else {
                    fatalError("Unable to find package dependencies key's path")
                }

                keySequence.removeFirst()

                let packageURL = URL(fileURLWithPath: path)
                let package = try Package.inProject(fileURL: packageURL)
                return identifier.ruleType.init(package: package, packageURL: packageURL, parameters: keySequence, buildSystem: self)
            } else {
                fatalError("Invalid identifier in key")
            }
        } catch {
            fatalError(error.localizedDescription)
        }

    }
}
