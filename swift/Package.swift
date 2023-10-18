// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SatsNav",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
    ],
    dependencies: [
        .package(url: "https://github.com/lukepistrol/KrakenAPI.git", .upToNextMajor(from: "2.1.0")),
        .package(url: "https://github.com/swiftcsv/SwiftCSV.git", .upToNextMinor(from: "0.9.1")),
        .package(url: "https://github.com/FlorianHubl/ElectrumKit", branch: "main"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .executableTarget(
            name: "SatsNav", dependencies: ["KrakenAPI", "SwiftCSV", "ElectrumKit"]
        ),
    ]
)
