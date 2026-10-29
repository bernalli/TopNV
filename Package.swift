// swift-tools-version:5.9
import PackageDescription

let package = Package(
  name: "topNV",
  platforms: [.macOS(.v14)],
  targets: [
    .target(name: "TopNVCore"),
    .executableTarget(name: "TopNV", dependencies: ["TopNVCore"]),
    .testTarget(name: "TopNVCoreTests", dependencies: ["TopNVCore"]),
  ]
)
