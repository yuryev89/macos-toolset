// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "MacOSToolset", platforms: [.macOS(.v13)], products: [
    .executable(name: "MacOSToolset", targets: ["MacOSToolset"])
], targets: [
    .target(name: "CSnapshot", publicHeadersPath: "include"),
    .target(name: "ToolsetCore"),
    .target(name: "ClosedLidSupport", dependencies: ["ToolsetCore"]),
    .target(name: "ClosedLidIPC"),
    .executableTarget(name: "ClosedLidHelper", dependencies: ["ToolsetCore", "ClosedLidSupport", "ClosedLidIPC"]),
    .executableTarget(name: "MacOSToolset", dependencies: ["ToolsetCore", "CSnapshot", "ClosedLidSupport", "ClosedLidIPC"]),
    .executableTarget(name: "CoreChecks", dependencies: ["ToolsetCore", "CSnapshot", "ClosedLidSupport"], path: "Tests/ToolsetCoreTests")
])
