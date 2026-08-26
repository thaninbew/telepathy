// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "Telepathy",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "Telepathy", targets: ["Telepathy"])
  ],
  targets: [
    .executableTarget(
      name: "Telepathy",
      path: "Sources/Telepathy",
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .testTarget(
      name: "TelepathyTests",
      dependencies: ["Telepathy"],
      path: "Tests/TelepathyTests",
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
  ]
)
