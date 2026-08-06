// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ScreenShifter",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ScreenShifterDomain", targets: ["ScreenShifterDomain"])
    ],
    targets: [
        .target(name: "ScreenShifterDomain"),
        .testTarget(
            name: "ScreenShifterDomainTests",
            dependencies: ["ScreenShifterDomain"]
        )
    ]
)