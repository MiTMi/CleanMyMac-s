// swift-tools-version:5.10
//
// Spruce — an original macOS cleaning, protection and monitoring utility.
//
// Targets
//   SpruceCore  Platform-independent logic (models, rule catalogs, safety guard,
//               scanners, algorithms). Builds and tests on Linux and macOS.
//   SpruceMac   macOS system layer (Mach/IOKit metrics, NSWorkspace, Trash,
//               SMAppService, privileged commands, module engines). macOS only.
//   Spruce      The SwiftUI app (main window, menu bar monitor). macOS only.
import PackageDescription

var targets: [Target] = [
    .target(
        name: "SpruceCore",
        path: "Sources/SpruceCore"
    ),
    .testTarget(
        name: "SpruceCoreTests",
        dependencies: ["SpruceCore"],
        path: "Tests/SpruceCoreTests"
    ),
]

var products: [Product] = [
    .library(name: "SpruceCore", targets: ["SpruceCore"]),
]

#if os(macOS)
targets += [
    .target(
        name: "SpruceMac",
        dependencies: ["SpruceCore"],
        path: "Sources/SpruceMac",
        linkerSettings: [
            .linkedFramework("IOKit"),
            .linkedFramework("Security"),
            .linkedFramework("ServiceManagement"),
            .linkedFramework("CoreServices"),
        ]
    ),
    .executableTarget(
        name: "Spruce",
        dependencies: ["SpruceCore", "SpruceMac"],
        path: "Sources/Spruce"
    ),
]
products += [
    .executable(name: "Spruce", targets: ["Spruce"]),
]
#endif

let package = Package(
    name: "Spruce",
    platforms: [.macOS(.v14)],
    products: products,
    targets: targets
)
