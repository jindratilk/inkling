// swift-tools-version:6.0
import Foundation
import PackageDescription

let projectRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let engineLibDir = projectRoot.appendingPathComponent("engine/target/release").path

let package = Package(
    name: "Inkling",
    platforms: [.macOS("26.0")],
    targets: [
        .target(name: "CInklingEngine", path: "Sources/CInklingEngine"),
        .executableTarget(
            name: "Inkling",
            dependencies: ["CInklingEngine"],
            path: "Sources/Inkling",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .unsafeFlags(["-L", engineLibDir]),
                .linkedLibrary("inkling_engine"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
    ]
)
