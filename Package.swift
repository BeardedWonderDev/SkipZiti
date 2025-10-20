// swift-tools-version: 6.0
// This is a Skip (https://skip.tools) package.
import PackageDescription
import class Foundation.Process
import class Foundation.Pipe
import Foundation

#if os(macOS)
private func profileRuntimeLinkerFlags() -> [String] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = ["clang", "--print-runtime-dir"]
    let output = Pipe()
    process.standardOutput = output
    process.standardError = Pipe()
    do {
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return [] }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard var dir = String(data: data, encoding: .utf8) else { return [] }
        dir = dir.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !dir.isEmpty else { return [] }
        let runtimePath = URL(fileURLWithPath: dir).appendingPathComponent("libclang_rt.profile_osx.a").path
        if FileManager.default.fileExists(atPath: runtimePath) {
            return ["-Xlinker", "-force_load", "-Xlinker", runtimePath]
        }
    } catch {
        // Ignore and fall back to no additional linker flags.
    }
    return []
}
#else
private func profileRuntimeLinkerFlags() -> [String] { [] }
#endif

let profileRuntimeFlags = profileRuntimeLinkerFlags()

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
            linkerSettings: profileRuntimeFlags.isEmpty ? [] : [
                .unsafeFlags(profileRuntimeFlags, .when(platforms: [.macOS]))
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
            linkerSettings: profileRuntimeFlags.isEmpty ? [] : [
                .unsafeFlags(profileRuntimeFlags, .when(platforms: [.macOS]))
            ],
            plugins: [
                .plugin(name: "skipstone", package: "skip")
            ]
        )
    ]
)
