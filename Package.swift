// swift-tools-version:5.9
import PackageDescription

let package = Package(
  name: "topNV",
  platforms: [.macOS(.v14)],
  dependencies: [
    .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"),
  ],
  targets: [
    .target(name: "TopNVCore"),
    .executableTarget(name: "TopNV", dependencies: ["TopNVCore", .product(name: "Sparkle", package: "Sparkle")]),
    .testTarget(name: "TopNVCoreTests", dependencies: ["TopNVCore"]),
  ]
)
