// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FolderDock",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "FolderDock", targets: ["FolderDock"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.2")
    ],
    targets: [
        .target(name: "FolderDockCore"),
        .executableTarget(
            name: "FolderDock",
            dependencies: [
                "FolderDockCore",
                .product(name: "Sparkle", package: "Sparkle")
            ]
        ),
        .executableTarget(
            name: "FolderDockGuardrails",
            dependencies: ["FolderDockCore"],
            path: "Tests/FolderDockGuardrails"
        )
    ]
)
