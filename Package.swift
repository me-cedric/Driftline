// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "Driftline",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "DriftlineCore", targets: ["DriftlineCore"]),
        .library(name: "DriftlineMCP", targets: ["DriftlineMCP"]),
        .library(name: "DriftlineWidget", targets: ["DriftlineWidget"]),
        .executable(name: "Driftline", targets: ["DriftlineApp"]),
        .executable(name: "driftline-mcp", targets: ["driftline-mcp"]),
        .executable(name: "driftline", targets: ["driftline"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", exact: "3.15.1"),
        .package(url: "https://github.com/apple/swift-nio.git", "2.80.0"..<"2.98.0"),
        .package(url: "https://github.com/apple/swift-nio-ssh.git", exact: "0.11.0"),
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", exact: "0.63.2"),
        .package(url: "https://github.com/nicklockwood/SwiftFormat", exact: "0.61.1")
    ],
    targets: [
        .target(
            name: "DriftlineCore",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOSSH", package: "swift-nio-ssh")
            ]
        ),
        .target(
            name: "DriftlineMCP",
            dependencies: [
                "DriftlineCore",
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio")
            ]
        ),
        .target(
            name: "DriftlineWidget",
            dependencies: [
                "DriftlineCore"
            ]
        ),
        .executableTarget(
            name: "DriftlineApp",
            dependencies: [
                "DriftlineCore",
                "DriftlineMCP"
            ]
        ),
        .executableTarget(
            name: "driftline",
            dependencies: [
                "DriftlineCore",
                "DriftlineMCP"
            ]
        ),
        .executableTarget(
            name: "driftline-mcp",
            dependencies: [
                "DriftlineCore",
                "DriftlineMCP"
            ]
        ),
        .testTarget(
            name: "DriftlineCoreTests",
            dependencies: [
                "DriftlineCore",
                "DriftlineApp",
                .product(name: "Crypto", package: "swift-crypto")
            ]
        ),
        .testTarget(
            name: "DriftlineMCPTests",
            dependencies: [
                "DriftlineMCP",
                "DriftlineCore"
            ]
        )
    ]
)
