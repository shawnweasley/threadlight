// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Threadlight",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Threadlight", targets: ["Threadlight"])],
    targets: [
        .target(name: "ThreadlightCore", linkerSettings: [.linkedLibrary("sqlite3")]),
        .executableTarget(name: "Threadlight", dependencies: ["ThreadlightCore"], resources: [.process("Resources")], linkerSettings: [.linkedFramework("AppKit")]),
        .testTarget(name: "ThreadlightCoreTests", dependencies: ["ThreadlightCore"]),
        .testTarget(name: "ThreadlightUITests", dependencies: ["Threadlight", "ThreadlightCore"])
    ]
)
