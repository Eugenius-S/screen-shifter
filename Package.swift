// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ScreenShifter",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ScreenShifterDomain", targets: ["ScreenShifterDomain"]),
        .library(name: "DisplayCore", targets: ["DisplayCore"]),
        .executable(name: "ScreenShifter", targets: ["ScreenShifterApp"])
    ],
    targets: [
        .target(name: "ScreenShifterDomain"),
        .target(
            name: "DisplayCore",
            dependencies: ["ScreenShifterDomain"]
        ),
        .executableTarget(
            name: "ScreenShifterApp",
            dependencies: ["DisplayCore", "ScreenShifterDomain"]
        ),
        .testTarget(
            name: "ScreenShifterDomainTests",
            dependencies: ["ScreenShifterDomain"]
        ),
        .testTarget(
            name: "DisplayCoreTests",
            dependencies: ["DisplayCore"]
        )
    ]
)