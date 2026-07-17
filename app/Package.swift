// swift-tools-version: 6.0
import PackageDescription

let lang: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "TouchMac",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "TouchMacCore", swiftSettings: lang),
        .executableTarget(name: "touchmacd", swiftSettings: lang),
        .executableTarget(name: "TouchMac", dependencies: ["TouchMacCore"], swiftSettings: lang),
        .executableTarget(name: "selftest", dependencies: ["TouchMacCore"], swiftSettings: lang),
    ]
)
