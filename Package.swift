// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ScreenShifter",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ScreenShifterDomain", targets: ["ScreenShifterDomain"]),
        .executable(name: "ScreenShifter", targets: ["ScreenShifterApp"])
    ],
    targets: [
        .target(name: "ScreenShifterDomain"),
        .executableTarget(
            name: "ScreenShifterApp",
            dependencies: ["ScreenShifterDomain"]
        ),
        .testTarget(
            name: "ScreenShifterDomainTests",
            dependencies: ["ScreenShifterDomain"]
        )
    ]
)