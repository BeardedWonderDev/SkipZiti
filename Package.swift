// swift-tools-version: 6.0
// This is a Skip (https://skip.tools) package.
import PackageDescription

let package = Package(
    name: "SkipZiti",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "SkipZiti", type: .dynamic, targets: ["SkipZiti"])
    ],
    dependencies: [
        .package(url: "https://source.skip.tools/skip.git", from: "1.6.27"),
        .package(url: "https://source.skip.tools/skip-fuse.git", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "SkipZiti",
            dependencies: [
                .product(name: "SkipFuse", package: "skip-fuse")
            ],
            resources: [
                .process("Resources")
            ],
            plugins: [
                .plugin(name: "skipstone", package: "skip")
            ]
        ),
        .testTarget(
            name: "SkipZitiTests",
            dependencies: [
                "SkipZiti",
                .product(name: "SkipTest", package: "skip")
            ],
            plugins: [
                .plugin(name: "skipstone", package: "skip")
            ]
        )
    ]
)
