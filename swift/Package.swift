// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SatsNav",
    platforms: [
        .macOS(.v12),
        .iOS(.v13),
    ],
    dependencies: [
        .package(url: "https://github.com/lukepistrol/KrakenAPI.git", .upToNextMajor(from: "2.1.0")),
        .package(url: "https://github.com/swiftcsv/SwiftCSV.git", .upToNextMinor(from: "0.9.1")),
        .package(url: "https://github.com/tayloraswift/swift-json", .upToNextMinor(from: "0.6.0")),
        .package(url: "https://github.com/FlorianHubl/ElectrumKit", branch: "main"),
        .package(url: "https://github.com/apple/swift-collections.git", .upToNextMajor(from: "1.0.5")),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .executableTarget(
            name: "SatsNav",
            dependencies: [
                "KrakenAPI",
                "SwiftCSV",
                "ElectrumKit",
                .product(name: "JSON", package: "swift-json"),
                .product(name: "JSONDecoding", package: "swift-json"),
                .product(name: "Collections", package: "swift-collections"),
            ]
        ),
    ]
)
