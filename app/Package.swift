// swift-tools-version: 6.0
import PackageDescription

let lang: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "TouchMac",
    platforms: [.macOS(.v14)],
    dependencies: [
        // in-app updates from GitHub Releases, EdDSA-signed
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0")
    ],
    targets: [
        .target(name: "TouchMacCore", swiftSettings: lang),
        .executableTarget(name: "touchmacd", dependencies: ["TouchMacCore"], swiftSettings: lang),
        .executableTarget(
            name: "TouchMac",
            dependencies: ["TouchMacCore", .product(name: "Sparkle", package: "Sparkle")],
            swiftSettings: lang,
            // make_app.sh puts Sparkle.framework in Contents/Frameworks
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .executableTarget(name: "selftest", dependencies: ["TouchMacCore"], swiftSettings: lang),
    ]
)
