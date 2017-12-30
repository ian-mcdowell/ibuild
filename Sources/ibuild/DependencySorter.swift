import Foundation

struct DependencySorter {

    static func buildOrder(forBuilding packages: [Package]) -> [Package] {
        // Assume packages was retrieved from the downloader, which does a depth-first search of dependencies.
        // All that is needed is to reverse the list, and remove duplicates.

        let reversed = packages.reversed()
        var seenURLs = Set<String>()
        return reversed.filter {
            seenURLs.insert($0.url).inserted
        }
    }
}