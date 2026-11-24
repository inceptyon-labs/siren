// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "SirenKit",
  platforms: [
    .iOS(.v17),
    .watchOS(.v10),
    .tvOS(.v17),
  ],
  products: [
    .library(
      name: "SirenKit",
      targets: ["SirenKit"]
    )
  ],
  dependencies: [
    .package(path: "../API"),
    .package(path: "../Models"),
  ],
  targets: [
    .target(
      name: "SirenKit",
      dependencies: [
        .product(name: "API", package: "API"),
        .product(name: "Models", package: "Models"),
      ]
    )
  ]
)
