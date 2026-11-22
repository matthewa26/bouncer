// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Bouncer",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "bouncer", targets: ["BouncerCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-syntax", from: "604.0.0"),
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.3.0"),
        .package(url: "https://github.com/tree-sitter/swift-tree-sitter", from: "0.25.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-go", from: "0.25.0"),
        // 9.17 raised its minimum to macOS 14; 9.16 still supports Bouncer's macOS 13.
        .package(url: "https://github.com/tuist/XcodeProj", .upToNextMinor(from: "9.16.1"))
    ],
    targets: [
        .target(name: "BouncerCore"),
        .target(name: "BouncerRules", dependencies: ["BouncerCore"]),
        .target(
            name: "BouncerSwiftAnalyzer",
            dependencies: [
                "BouncerCore",
                "BouncerRules",
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax")
            ]
        ),
        .target(name: "BouncerHeuristicAnalyzer", dependencies: ["BouncerCore", "BouncerRules"]),
        .target(
            name: "CTreeSitterPython",
            cSettings: [.headerSearchPath(".")]
        ),
        .target(
            name: "CTreeSitterTypeScript",
            exclude: ["LICENSE", "NOTICE.md"],
            cSettings: [.headerSearchPath("typescript/src")]
        ),
        .target(
            name: "CTreeSitterTSX",
            exclude: ["LICENSE", "NOTICE.md"],
            cSettings: [.headerSearchPath("tsx/src")]
        ),
        .target(
            name: "CTreeSitterJavaScript",
            exclude: ["LICENSE", "NOTICE.md"],
            cSettings: [.headerSearchPath("src")]
        ),
        .target(
            name: "CTreeSitterObjC",
            exclude: ["LICENSE", "NOTICE.md"],
            cSettings: [.headerSearchPath("src")]
        ),
        .target(
            name: "CTreeSitterRust",
            exclude: ["LICENSE", "NOTICE.md"],
            cSettings: [.headerSearchPath("src")]
        ),
        .target(
            name: "BouncerTreeSitterAnalyzer",
            dependencies: [
                "BouncerCore",
                "BouncerRules",
                "CTreeSitterPython",
                "CTreeSitterTypeScript",
                "CTreeSitterTSX",
                "CTreeSitterJavaScript",
                "CTreeSitterObjC",
                "CTreeSitterRust",
                .product(name: "SwiftTreeSitter", package: "swift-tree-sitter"),
                .product(name: "TreeSitterGo", package: "tree-sitter-go")
            ]
        ),
        .target(name: "BouncerCoverage", dependencies: ["BouncerCore"]),
        .target(name: "BouncerProject", dependencies: ["BouncerCore", "BouncerGit"]),
        .target(name: "BouncerReporting", dependencies: ["BouncerCore"]),
        .target(name: "BouncerGit", dependencies: ["BouncerCore"]),
        .target(name: "BouncerConfig", dependencies: ["BouncerCore", "BouncerRules"]),
        .target(name: "BouncerUpdateCheck", dependencies: ["BouncerCore"]),
        .target(name: "BouncerHooks", dependencies: ["BouncerCore"]),
        .target(
            name: "BouncerXcode",
            dependencies: [
                "BouncerCore",
                // Xcode projects only exist on macOS, so Linux and Windows builds don't carry the library.
                .product(name: "XcodeProj", package: "XcodeProj", condition: .when(platforms: [.macOS]))
            ]
        ),
        .executableTarget(
            name: "BouncerCLI",
            dependencies: [
                "BouncerCore",
                "BouncerRules",
                "BouncerSwiftAnalyzer",
                "BouncerHeuristicAnalyzer",
                "BouncerTreeSitterAnalyzer",
                "BouncerCoverage",
                "BouncerReporting",
                "BouncerGit",
                "BouncerConfig",
                "BouncerUpdateCheck",
                "BouncerHooks",
                "BouncerProject",
                "BouncerXcode",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .testTarget(name: "BouncerCoreTests", dependencies: ["BouncerCore"]),
        .testTarget(name: "BouncerRulesTests", dependencies: ["BouncerRules"]),
        .testTarget(name: "BouncerHeuristicAnalyzerTests", dependencies: ["BouncerHeuristicAnalyzer"]),
        .testTarget(name: "BouncerTreeSitterAnalyzerTests", dependencies: ["BouncerTreeSitterAnalyzer"]),
        .testTarget(name: "BouncerSwiftAnalyzerTests", dependencies: ["BouncerSwiftAnalyzer"]),
        .testTarget(name: "BouncerCoverageTests", dependencies: ["BouncerCoverage"]),
        .testTarget(name: "BouncerConfigTests", dependencies: ["BouncerConfig"]),
        .testTarget(name: "BouncerReportingTests", dependencies: ["BouncerReporting"]),
        .testTarget(name: "BouncerGitTests", dependencies: ["BouncerGit"]),
        .testTarget(name: "BouncerHooksTests", dependencies: ["BouncerHooks"]),
        .testTarget(
            name: "BouncerProjectTests",
            dependencies: ["BouncerProject", "BouncerSwiftAnalyzer", "BouncerHeuristicAnalyzer", "BouncerConfig"]
        ),
        .testTarget(name: "BouncerUpdateCheckTests", dependencies: ["BouncerUpdateCheck"]),
        .testTarget(name: "BouncerXcodeTests", dependencies: ["BouncerXcode"])
    ]
)
