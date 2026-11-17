// swift-tools-version: 5.10
import PackageDescription

// One package with one target per device, so adding a device never edits the Xcode project.
// A device session adds its `<Name>KitTests` test target when it writes protocol code.
let kits = ["WalkingPadKit", "MiScaleKit", "PhilipsAirKit", "ZeppelinKit", "XiaomiFanKit", "DreameKit", "AenoKit"]

let package = Package(
    name: "HomeDeckKits",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "HomeDeckKits", targets: ["HubCore"] + kits)],
    targets: [
        .target(name: "HubCore"),
        .testTarget(name: "HubCoreTests", dependencies: ["HubCore"]),
        .testTarget(name: "WalkingPadKitTests", dependencies: ["WalkingPadKit"]),
        .testTarget(name: "MiScaleKitTests", dependencies: ["MiScaleKit"]),
        .testTarget(name: "DreameKitTests", dependencies: ["DreameKit"]),
        .testTarget(name: "ZeppelinKitTests", dependencies: ["ZeppelinKit"]),
        .testTarget(name: "PhilipsAirKitTests", dependencies: ["PhilipsAirKit"]),
        .testTarget(name: "XiaomiFanKitTests", dependencies: ["XiaomiFanKit"]),
        .testTarget(name: "CatalogTests", dependencies: ["HubCore"] + kits.map { Target.Dependency.byName(name: $0) }),
    ] + kits.map { Target.target(name: $0, resources: [.process("features.json")]) }
)
