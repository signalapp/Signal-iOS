// swift-tools-version:6.0

import PackageDescription

let package = Package(
    name: "blurhash",
    platforms: [
        .iOS(.v15),
    ],
    products: [
        .library(name: "blurhash", targets: ["blurhash"]),
    ],
    targets: [
        .target(name: "blurhash"),
    ],
    swiftLanguageModes: [.v5]
)
