// swift-tools-version:4.0

import PackageDescription

let package = Package(
    name: "ibuild",
    products: [
        .executable(name: "ibuild", targets: ["ibuild"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-llbuild.git", .branch("master")),
    ],
    targets: [
        .target(
            name: "ibuild",
            dependencies: ["llbuildSwift"]
	    ),
    ]
)
