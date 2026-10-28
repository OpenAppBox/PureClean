// swift-tools-version: 6.0
// PureCleanKit — the UI-independent engine of PureClean (scanning, ownership, rules, cleanup, persistence).
// No third-party dependencies: only Apple system frameworks and the system SQLite3 library.
import PackageDescription

let package = Package(
    name: "PureCleanKit",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PureCleanKit", targets: ["PureCleanKit"]),
    ],
    targets: [
        .target(
            name: "PureCleanKit",
            resources: [.process("Resources")],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "PureCleanKitTests",
            dependencies: ["PureCleanKit"]
        ),
    ]
)
