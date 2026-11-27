// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "VietGo",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "VietGoEngine",
            targets: ["VietGoEngine"]
        ),
        .executable(
            name: "VietGo",
            targets: ["VietGo"]
        )
    ],
    targets: [
        .target(
            name: "VietGoEngine",
            path: "Sources/VietGoEngine",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .executableTarget(
            name: "VietGo",
            dependencies: ["VietGoEngine"],
            path: "Sources/VietGoApp",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "VietGoEngineTests",
            dependencies: ["VietGoEngine"],
            path: "Tests/VietGoEngineTests",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
