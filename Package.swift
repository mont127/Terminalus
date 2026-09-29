// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Terminalus",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Terminalus", targets: ["Terminalus"]),
    ],
    dependencies: [
        // Vendored + patched by scripts/bootstrap-swiftterm.sh (Shaders.metal is copied, not compiled).
        .package(path: "Vendor/SwiftTerm"),
    ],
    targets: [
        .target(
            name: "TerminalusCore",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .executableTarget(
            name: "Terminalus",
            dependencies: [
                "TerminalusCore",
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("UserNotifications"),
                .linkedFramework("Quartz"),
                .linkedFramework("UniformTypeIdentifiers"),
            ]
        ),
        .testTarget(
            name: "TerminalusCoreTests",
            dependencies: ["TerminalusCore"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
