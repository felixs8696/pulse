// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Pulse",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Pulse", targets: ["Pulse"])],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "PulseCore", dependencies: ["CSQLite"]),
        .executableTarget(name: "Pulse", dependencies: ["PulseCore"], resources: [.copy("Resources/Logos")]),
        .testTarget(name: "PulseCoreTests", dependencies: ["PulseCore", "CSQLite"])
    ]
)
