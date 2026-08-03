// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FolderDock",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "FolderDock", targets: ["FolderDock"])
    ],
    targets: [
        .executableTarget(name: "FolderDock")
    ]
)
