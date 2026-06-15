// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "OpenfortSwift",
    platforms: [
            .iOS(.v16),
            .macOS(.v11),
        ],
    products: [
        .library(
            name: "OpenfortSwift",
            targets: ["OpenfortSwift"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-docc-plugin.git", from: "1.3.0")
    ],
    targets: [
        .target(
            name: "OpenfortSwift",
            resources: [
                    .process("Resources")
                ]
        ),
        
        .testTarget(
            name: "OpenfortSwiftTests",
            dependencies: ["OpenfortSwift"]
        ),
        
    ]
)
