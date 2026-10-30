// swift-tools-version: 6.2

// TimeTrackingCore: the shared library linked statically by every executable
// (spec_architecture.md §1.2, §5). Dependencies are pinned exactly; the same
// versions are pinned in the Xcode project's Package.resolved.

import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .treatAllWarnings(as: .error),
]

let package = Package(
    name: "TimeTrackingCore",
    platforms: [.macOS("27.0"), .iOS("27.0")],
    products: [
        .library(name: "TimeTrackingCore", targets: ["TimeTrackingCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", exact: "7.11.1"),
        .package(url: "https://github.com/LebJe/TOMLKit", exact: "0.6.0"),
    ],
    targets: [
        .target(
            name: "TimeTrackingCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "TOMLKit", package: "TOMLKit"),
            ],
            swiftSettings: swiftSettings
        ),
        // Development tool behind scripts/make_fixtures.swift; not linked by any app.
        .executableTarget(
            name: "MakeFixtures",
            dependencies: ["TimeTrackingCore"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "TimeTrackingCoreTests",
            dependencies: ["TimeTrackingCore"],
            swiftSettings: swiftSettings
        ),
    ],
    swiftLanguageModes: [.v6]
)
