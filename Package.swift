// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TeslaViewer",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "TeslaViewer", targets: ["TeslaViewer"])
    ],
    targets: [
        .executableTarget(
            name: "TeslaViewer",
            resources: [
                .process("Assets.xcassets")
            ]
        ),
        .testTarget(
            name: "TeslaViewerTests",
            dependencies: ["TeslaViewer"]
        )
    ]
)
