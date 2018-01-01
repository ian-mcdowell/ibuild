import Foundation

struct DependencySorter {

    static func buildOrder(forBuilding packages: [(package: Package, location: URL)]) -> [(package: Package, location: URL)] {
        // Assume packages was retrieved from the downloader, which does a depth-first search of dependencies.
        // All that is needed is to reverse the list, and remove duplicates.

        let reversed = packages.reversed()
        var seenNames = Set<String>()
        return reversed.filter {
            seenNames.insert($0.package.name).inserted
        }
    }
}