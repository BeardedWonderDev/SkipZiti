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
        .library(name: "SkipZiti", targets: ["SkipZiti"]),
        .library(name: "SkipZitiCore", targets: ["SkipZitiCore"]),
        .library(name: "SkipZitiIdentity", targets: ["SkipZitiIdentity"]),
        .library(name: "SkipZitiServices", targets: ["SkipZitiServices"]),
        .library(name: "SkipZitiUI", targets: ["SkipZitiUI"])
    ],
    dependencies: [
        .package(url: "https://source.skip.tools/skip.git", from: "1.6.27"),
        .package(url: "https://source.skip.tools/skip-fuse.git", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "SkipZitiCore",
            dependencies: []
        ),
        .target(
            name: "SkipZitiIdentity",
            dependencies: [
                "SkipZitiCore"
            ]
        ),
        .target(
            name: "SkipZitiServices",
            dependencies: [
                "SkipZitiCore",
                "SkipZitiIdentity"
            ]
        ),
        .target(
            name: "SkipZitiFuse",
            dependencies: [
                "SkipZitiServices",
                .product(name: "SkipFuse", package: "skip-fuse")
            ],
            resources: [
                .process("Skip")
            ],
            plugins: [
                .plugin(name: "skipstone", package: "skip")
            ]
        ),
        .target(
            name: "SkipZitiUI",
            dependencies: [
                "SkipZitiServices"
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .target(
            name: "SkipZiti",
            dependencies: [
                "SkipZitiCore",
                "SkipZitiIdentity",
                "SkipZitiServices",
                "SkipZitiFuse",
                "SkipZitiUI"
            ]
        ),
        .testTarget(
            name: "SkipZitiTests",
            dependencies: [
                "SkipZiti"
            ]
        )
    ]
)
