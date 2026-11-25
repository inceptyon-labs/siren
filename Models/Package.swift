// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "Models",
  platforms: [
    .iOS(.v17),
    .watchOS(.v10),
    .tvOS(.v17),  // SIREN: tvOS for the Apple TV app
  ],
  products: [
    .library(
      name: "Models",
      targets: ["Models"]
    )
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-log.git", exact: "1.17.2"),
    .package(path: "../API"),
  ],
  targets: [
    .target(
      name: "Models",
      dependencies: [
        .product(name: "Logging", package: "swift-log"),
        .product(name: "API", package: "API"),
      ]
    )
  ]
)
