// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Pastry",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .executable(
            name: "Pastry",
            targets: ["Pastry"]
        ),
        .executable(
            name: "PastryReleaseSmoke",
            targets: ["PastryReleaseSmoke"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "CSQLCipher",
            path: "Sources/CSQLCipher",
            sources: ["include/shim.c"],
            publicHeadersPath: "include",
            cSettings: [
                .define("SQLITE_HAS_CODEC"),
                .define("SQLCIPHER_CRYPTO_CC"),
            ],
            linkerSettings: [
                .unsafeFlags(["-LSources/CSQLCipher", "-lsqlcipher"]),
                .linkedFramework("CoreFoundation"),
                .linkedFramework("Security"),
            ]
        ),
        .executableTarget(
            name: "Pastry",
            dependencies: ["CSQLCipher"],
            path: "Sources/Pastry",
            resources: [.process("Resources")],
            linkerSettings: [
                .linkedFramework("Security"),
            ]
        ),
        .testTarget(
            name: "PastryTests",
            dependencies: ["Pastry", "CSQLCipher"],
            path: "Tests/PastryTests",
            exclude: ["__Snapshots__"]
        ),
        .executableTarget(
            name: "PastryReleaseSmoke",
            path: "Sources/PastryReleaseSmoke",
            linkerSettings: [.linkedFramework("AppKit")]
        ),
    ],
    // tools 6.0 后默认语言模式为 Swift 6；当前 toolchain 在 SendNonSendable
    // 诊断中会崩溃，先显式钉 v5，待编译器修复后再开严格并发。
    swiftLanguageModes: [.v5]
)
