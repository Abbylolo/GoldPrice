// swift-tools-version:6.0
import PackageDescription
import Foundation

let package = Package(
    name: "GoldPrice",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "GoldPrice", targets: ["GoldPrice"])
    ],
    dependencies: [],
    targets: [
        .target(name: "GoldPriceCore", path: "Sources/GoldPriceCore"),
        .executableTarget(
            name: "GoldPrice",
            dependencies: ["GoldPriceCore"],
            path: ".",
            exclude: [
                "Info.plist",
                "Assets/",
                "Archives/",
                "Build/",
                ".git/",
                ".DS_Store",
                ".cursor/",
                ".vscode/",
                "README.md",
                "CLAUDE.md",
                "Sources/",
                "Tests/",
                "scripts/",
                "AppIcon.icns",
                ".github/"
            ].filter { FileManager.default.fileExists(atPath: $0) },
            sources: ["GoldPriceApp.swift", "GoldPriceService.swift", "GoldPriceView.swift", "StatusBarController.swift", "AppStore.swift"]
        ),
        .testTarget(name: "GoldPriceCoreTests", dependencies: ["GoldPriceCore"], path: "Tests/GoldPriceCoreTests")
    ],
    swiftLanguageModes: [.v5]
)
