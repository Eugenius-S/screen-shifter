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
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.5")
    ],
    targets: [
        .target(name: "ScreenShifterDomain"),
        .target(
            name: "DisplayCore",
            dependencies: ["ScreenShifterDomain"]
        ),
        .executableTarget(
            name: "ScreenShifterApp",
            dependencies: [
                "DisplayCore",
                "ScreenShifterDomain",
                .product(name: "Sparkle", package: "sparkle")
            ]
        ),
        .testTarget(
            name: "ScreenShifterDomainTests",
            dependencies: ["ScreenShifterDomain"]
        ),
        .testTarget(
            name: "DisplayCoreTests",
            dependencies: ["DisplayCore", "ScreenShifterDomain"]
        ),
        .testTarget(
            name: "ScreenShifterAppTests",
            dependencies: ["ScreenShifterApp"]
        )
    ]
)
