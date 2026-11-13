// swift-tools-version: 5.10
import PackageDescription

// One package with one target per device, so adding a device never edits the Xcode project.
let package = Package(
    name: "HomeDeckKits",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "HomeDeckKits", targets: ["HubCore"])],
    targets: [
        .target(name: "HubCore"),
        .testTarget(name: "HubCoreTests", dependencies: ["HubCore"]),
    ]
)
